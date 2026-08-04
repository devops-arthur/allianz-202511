"""
AWS Config custom rule: is this resource encrypted with the *current generation* of its
centrally-managed BYOK key?

The generic managed rules (s3-default-encryption-kms, rds-storage-encrypted,
dynamodb-table-encrypted-kms) only answer "is it encrypted with a CMK". After a rotation, a bucket
still encrypted under prod-s3-gen1 is perfectly "encrypted" and perfectly non-rotated. This rule
closes that gap.

The single source of truth for "current generation" is the service alias in the security account
(alias/<environment>-<service>). The rule resolves it with kms:DescribeKey at evaluation time, so no
key ARN is ever hardcoded in the workload accounts and a rotation needs no redeploy here.

Triggers handled:
  * ConfigurationItemChangeNotification          - immediate feedback on create/update
  * OversizedConfigurationItemChangeNotification - large items (typically S3 buckets)
  * ScheduledNotification                        - periodic full sweep, the "at any given time" view

Resource state is always read from the owning service API rather than from the Config item, so the
evaluation is correct even when the configuration item is oversized or lagging.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)

ENVIRONMENT = os.environ["ENVIRONMENT"]
KEY_ACCOUNT_ID = os.environ["KEY_ACCOUNT_ID"]
KEY_REGION = os.environ.get("KEY_REGION") or os.environ["AWS_REGION"]
PARTITION = os.environ.get("PARTITION", "aws")
ALIAS_TEMPLATE = os.environ.get("ALIAS_TEMPLATE", "alias/{environment}-{service}")
SERVICE_BY_RESOURCE_TYPE = json.loads(os.environ["SERVICE_BY_RESOURCE_TYPE"])
REGION = os.environ["AWS_REGION"]

config = boto3.client("config")
kms = boto3.client("kms", region_name=KEY_REGION)
s3 = boto3.client("s3")
rds = boto3.client("rds")
dynamodb = boto3.client("dynamodb")

MAX_ANNOTATION = 256

# Key reference -> key ARN, cached per invocation only. A periodic sweep resolves the same alias for
# hundreds of resources; caching across invocations would keep serving a pre-rotation target.
_current_key_cache = {}


class NotApplicable(Exception):
    """The resource no longer exists or is out of scope."""


# ---------------------------------------------------------------------------------------------------
# Key resolution
# ---------------------------------------------------------------------------------------------------
def alias_arn(service):
    alias = ALIAS_TEMPLATE.format(environment=ENVIRONMENT, service=service)
    return f"arn:{PARTITION}:kms:{KEY_REGION}:{KEY_ACCOUNT_ID}:{alias}"


def resolve_key_arn(key_reference):
    """Resolve a key id / alias / alias ARN to the key ARN it currently points at."""
    if key_reference in _current_key_cache:
        return _current_key_cache[key_reference]

    metadata = kms.describe_key(KeyId=key_reference)["KeyMetadata"]
    resolved = metadata["Arn"]
    _current_key_cache[key_reference] = resolved
    return resolved


def current_key_arn(service):
    return resolve_key_arn(alias_arn(service))


def compare_with_current(service, key_reference, extra=""):
    """Compare the key a resource is actually using with the current generation of the service key."""
    try:
        expected = current_key_arn(service)
    except ClientError as error:
        # Never claim compliance we could not verify.
        return "NON_COMPLIANT", f"cannot resolve {alias_arn(service)}: {error.response['Error']['Code']}"

    references_alias = ":alias/" in key_reference or key_reference.startswith("alias/")

    try:
        actual = resolve_key_arn(key_reference)
    except ClientError as error:
        return "NON_COMPLIANT", f"cannot describe key {key_reference}: {error.response['Error']['Code']}"

    if actual != expected:
        return "NON_COMPLIANT", (
            f"rotation not applied: encrypted with {actual}, current {ENVIRONMENT}-{service} "
            f"key is {expected}. {extra}"
        )

    if references_alias:
        return "COMPLIANT", f"references {key_reference}, which resolves to the current key. {extra}"

    return "COMPLIANT", f"encrypted with the current {ENVIRONMENT}-{service} key. {extra}"


# ---------------------------------------------------------------------------------------------------
# Per-service evaluation, always against the owning service API
# ---------------------------------------------------------------------------------------------------
def evaluate_s3_bucket(bucket_name):
    try:
        rules = s3.get_bucket_encryption(Bucket=bucket_name)["ServerSideEncryptionConfiguration"]["Rules"]
    except ClientError as error:
        code = error.response["Error"]["Code"]
        if code in ("NoSuchBucket", "NoSuchBucketPolicy"):
            raise NotApplicable(bucket_name)
        if code == "ServerSideEncryptionConfigurationNotFoundError":
            return "NON_COMPLIANT", "bucket has no default encryption configuration"
        raise

    default = (rules[0] if rules else {}).get("ApplyServerSideEncryptionByDefault", {})
    algorithm = default.get("SSEAlgorithm")

    if algorithm != "aws:kms":
        return "NON_COMPLIANT", f"default encryption is {algorithm or 'absent'}, expected aws:kms with a BYOK key"

    key_reference = default.get("KMSMasterKeyID")
    if not key_reference:
        return "NON_COMPLIANT", "bucket uses the AWS managed key aws/s3, not the BYOK key"

    bucket_key = "S3 Bucket Keys enabled" if rules[0].get("BucketKeyEnabled") else "S3 Bucket Keys disabled"
    return compare_with_current("s3", key_reference, extra=bucket_key)


def evaluate_db_instance(identifier):
    try:
        instances = rds.describe_db_instances(DBInstanceIdentifier=identifier)["DBInstances"]
    except ClientError as error:
        if error.response["Error"]["Code"] == "DBInstanceNotFound":
            raise NotApplicable(identifier)
        raise

    instance = instances[0]

    # Instances belonging to a cluster are encrypted at cluster level; evaluate the cluster instead.
    if instance.get("DBClusterIdentifier"):
        return "NOT_APPLICABLE", "cluster member, encryption evaluated on the DB cluster"

    if not instance.get("StorageEncrypted"):
        return "NON_COMPLIANT", "storage is not encrypted"

    return compare_with_current("rds", instance["KmsKeyId"])


def evaluate_db_cluster(identifier):
    try:
        clusters = rds.describe_db_clusters(DBClusterIdentifier=identifier)["DBClusters"]
    except ClientError as error:
        if error.response["Error"]["Code"] == "DBClusterNotFoundFault":
            raise NotApplicable(identifier)
        raise

    cluster = clusters[0]
    if not cluster.get("StorageEncrypted"):
        return "NON_COMPLIANT", "cluster storage is not encrypted"

    return compare_with_current("rds", cluster["KmsKeyId"])


def evaluate_dynamodb_table(table_name):
    try:
        table = dynamodb.describe_table(TableName=table_name)["Table"]
    except ClientError as error:
        if error.response["Error"]["Code"] == "ResourceNotFoundException":
            raise NotApplicable(table_name)
        raise

    sse = table.get("SSEDescription") or {}

    # No SSEDescription at all means the table uses the AWS owned key.
    if sse.get("SSEType") != "KMS" or not sse.get("KMSMasterKeyArn"):
        return "NON_COMPLIANT", "table uses the AWS owned/managed key, not the BYOK key"

    if sse.get("Status") == "UPDATING":
        return "NON_COMPLIANT", "table is still re-encrypting to a new KMS key (SSE status UPDATING)"

    return compare_with_current("ddb", sse["KMSMasterKeyArn"])


EVALUATORS = {
    "AWS::S3::Bucket": evaluate_s3_bucket,
    "AWS::RDS::DBInstance": evaluate_db_instance,
    "AWS::RDS::DBCluster": evaluate_db_cluster,
    "AWS::DynamoDB::Table": evaluate_dynamodb_table,
}


def evaluate(resource_type, resource_name):
    if resource_type not in EVALUATORS:
        return "NOT_APPLICABLE", "resource type not in scope"

    try:
        return EVALUATORS[resource_type](resource_name)
    except NotApplicable:
        return "NOT_APPLICABLE", "resource no longer exists"


# ---------------------------------------------------------------------------------------------------
# Resource discovery for the periodic sweep
# ---------------------------------------------------------------------------------------------------
def discover():
    """Yield (resource_type, config_resource_id, name_for_api) for everything in scope."""
    if "AWS::S3::Bucket" in SERVICE_BY_RESOURCE_TYPE:
        for bucket in s3.list_buckets().get("Buckets", []):
            name = bucket["Name"]
            try:
                location = s3.get_bucket_location(Bucket=name)["LocationConstraint"] or "us-east-1"
            except ClientError:
                continue
            if location == REGION:
                yield "AWS::S3::Bucket", name, name

    if "AWS::RDS::DBInstance" in SERVICE_BY_RESOURCE_TYPE:
        for page in rds.get_paginator("describe_db_instances").paginate():
            for instance in page["DBInstances"]:
                # AWS Config identifies RDS instances by DbiResourceId, not by the identifier.
                yield "AWS::RDS::DBInstance", instance["DbiResourceId"], instance["DBInstanceIdentifier"]

    if "AWS::RDS::DBCluster" in SERVICE_BY_RESOURCE_TYPE:
        for page in rds.get_paginator("describe_db_clusters").paginate():
            for cluster in page["DBClusters"]:
                yield "AWS::RDS::DBCluster", cluster["DbClusterResourceId"], cluster["DBClusterIdentifier"]

    if "AWS::DynamoDB::Table" in SERVICE_BY_RESOURCE_TYPE:
        for page in dynamodb.get_paginator("list_tables").paginate():
            for table_name in page["TableNames"]:
                yield "AWS::DynamoDB::Table", table_name, table_name


# ---------------------------------------------------------------------------------------------------
# Config plumbing
# ---------------------------------------------------------------------------------------------------
def put_evaluations(evaluations, result_token):
    for start in range(0, len(evaluations), 100):
        config.put_evaluations(
            Evaluations=evaluations[start:start + 100],
            ResultToken=result_token,
        )


def evaluation(resource_type, resource_id, status, annotation, timestamp):
    return {
        "ComplianceResourceType": resource_type,
        "ComplianceResourceId": resource_id,
        "ComplianceType": status,
        "Annotation": annotation.strip()[:MAX_ANNOTATION],
        "OrderingTimestamp": timestamp,
    }


def resource_from_change_event(invoking_event):
    item = invoking_event.get("configurationItem") or invoking_event.get("configurationItemSummary")

    resource_type = item["resourceType"]
    resource_id = item["resourceId"]
    # resourceName is the identifier the service APIs expect (RDS in particular).
    resource_name = item.get("resourceName") or resource_id
    timestamp = item.get("configurationItemCaptureTime") or invoking_event["notificationCreationTime"]
    deleted = item.get("configurationItemStatus") in ("ResourceDeleted", "ResourceDeletedNotRecorded")

    return resource_type, resource_id, resource_name, timestamp, deleted


def lambda_handler(event, context):
    _current_key_cache.clear()

    invoking_event = json.loads(event["invokingEvent"])
    message_type = invoking_event["messageType"]
    result_token = event["resultToken"]

    if message_type in ("ConfigurationItemChangeNotification", "OversizedConfigurationItemChangeNotification"):
        resource_type, resource_id, resource_name, timestamp, deleted = resource_from_change_event(invoking_event)

        if deleted:
            status, annotation = "NOT_APPLICABLE", "resource deleted"
        else:
            status, annotation = evaluate(resource_type, resource_name)

        log.info("%s %s -> %s (%s)", resource_type, resource_id, status, annotation)
        put_evaluations(
            [evaluation(resource_type, resource_id, status, annotation, timestamp)],
            result_token,
        )
        return

    if message_type == "ScheduledNotification":
        timestamp = invoking_event["notificationCreationTime"]
        evaluations = []
        non_compliant = 0

        for resource_type, resource_id, resource_name in discover():
            status, annotation = evaluate(resource_type, resource_name)
            if status == "NON_COMPLIANT":
                non_compliant += 1
                log.warning("NON_COMPLIANT %s %s: %s", resource_type, resource_name, annotation)
            evaluations.append(evaluation(resource_type, resource_id, status, annotation, timestamp))

        log.info("evaluated %d resources, %d not rotated", len(evaluations), non_compliant)
        put_evaluations(evaluations, result_token)
        return

    log.warning("unsupported message type %s", message_type)
