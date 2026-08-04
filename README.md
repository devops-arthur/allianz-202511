# allianz-202511

## AWS KMS BYOK key rotation response (Dev/Int/Prod)

Scope: `dev-s3`, `int-s3`, `prod-s3`, `dev-rds`, `int-rds`, `prod-rds`, `dev-ddb`, `int-ddb`, `prod-ddb`.

### 1) Main challenges and impacts

- **BYOK lifecycle complexity**: AWS KMS automatic yearly rotation is not applicable to imported key material; rotation must be orchestrated manually (generate/import/re-point alias/validate).
- **Cross-account coordination**: keys live in dedicated security accounts while workloads run in other accounts; IAM, key policy, grants, and service roles must stay aligned during cutover.
- **Alias cutover risk**: changing alias target is fast, but any hard-coded key ARN usage (instead of alias) will miss rotation and become non-compliant.
- **Service behavior differences**:
  - **S3**: new writes use new key, old objects remain encrypted with old key until re-encrypted (copy/Batch Operations).
  - **RDS**: storage encryption key is set at creation; full key migration generally needs snapshot/copy/restore path.
  - **DynamoDB**: key updates are supported, but data/key transition and throughput impact must be monitored.
- **Operational impact**: short control-plane change window, potential re-encryption backlog, cost increases (KMS/API, data copy), and temporary performance impact.
- **Compliance impact**: evidence must prove key material version change, alias mapping change, policy continuity, and post-rotation resource conformity.

### 2) High-level rotation steps

1. **Prepare**  
   - Inventory all 9 key aliases and consuming resources (S3 buckets, RDS instances/clusters, DynamoDB tables).  
   - Confirm every consumer references alias (or CMK ID resolved from alias) and not static legacy key ARN.
2. **Create new key material version**  
   - Generate new cryptographic material on on-prem HSM per env/service.
3. **Import into new KMS keys (recommended)**  
   - Create new KMS key per scope (`env-service`) in security account, apply least-privilege key policy and grants, import material, enable key.
4. **Cutover via alias**  
   - Move each alias to the new key after pre-checks in Dev, then Int, then Prod.
5. **Service-level migration**  
   - **S3**: trigger re-encryption campaign for required objects (S3 Batch Operations / copy in place).  
   - **RDS**: execute snapshot-copy-restore migration plan for instances requiring full key change.  
   - **DynamoDB**: update table KMS key setting and validate status.
6. **Validation and rollback readiness**  
   - Validate encrypt/decrypt, application access, CloudTrail events, and service health metrics.  
   - Keep previous keys enabled during stabilization period; disable/schedule deletion only after sign-off.
7. **Audit evidence**  
   - Store change records, key ARNs, alias history, approvals, test results, and compliance reports.

### 3) Continuous compliance monitoring (AWS managed services)

Use managed services to detect resources not using the expected rotated key/alias:

- **AWS Config**  
  - Enable recorder and aggregator across all accounts/regions.  
  - Use managed rules where available plus **custom AWS Config rules** (Lambda) for:
    - S3 bucket default encryption key check against approved alias/key map.
    - RDS instance/cluster KMS key check against approved key per environment.
    - DynamoDB table SSE KMS key check against approved key per environment.
- **AWS Security Hub**  
  - Ingest Config findings and centralize compliance score/cards.
- **EventBridge + SNS / OpsCenter**  
  - Real-time notifications for NON_COMPLIANT changes and ticketing/incident routing.
- **CloudTrail + CloudWatch**  
  - Monitor `UpdateAlias`, `DisableKey`, `ScheduleKeyDeletion`, encryption-setting changes for detective control and audit.

This provides “at any given time” visibility through near real-time Config evaluations plus periodic re-evaluation and centralized aggregation.

### 4) Securing key material transport (HSM -> AWS KMS)

- Use the **AWS KMS import key material process** only:
  - Retrieve KMS wrapping public key/import token over TLS.
  - Wrap key material on-prem using the required RSA/AES wrapping algorithm.
  - Send only wrapped material to AWS KMS (`ImportKeyMaterial`).
- Enforce **strict custody controls**:
  - Dual control / 4-eyes process in HSM operations.
  - Dedicated hardened workstation or isolated pipeline runner.
  - MFA + short-lived credentials + least privilege IAM.
- Protect channels and artifacts:
  - Private connectivity (VPN/Direct Connect) where possible.
  - No plaintext key export, no persistent plaintext at rest, secure memory handling.
  - Signed operation logs, tamper-evident audit trail, time synchronization.
- Apply **post-import hygiene**:
  - Verify key checksum/metadata, run functional tests, rotate transport credentials, and archive audit evidence.
