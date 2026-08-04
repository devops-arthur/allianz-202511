#!/bin/bash
set -euo pipefail

# Mount EFS for shared GitLab data (git repos, uploads, artifacts)
yum install -y amazon-efs-utils
mkdir -p /var/opt/gitlab/git-data /var/opt/gitlab/uploads /var/opt/gitlab/artifacts

mount -t efs -o tls ${efs_dns}:/ /var/opt/gitlab/git-data
echo "${efs_dns}:/ /var/opt/gitlab/git-data efs _netdev,tls 0 0" >> /etc/fstab

# Write GitLab external_url and database config
cat >> /etc/gitlab/gitlab.rb << 'GITLABCFG'
postgresql['enable'] = false
gitlab_rails['db_adapter']  = 'postgresql'
gitlab_rails['db_host']     = '${db_host}'
gitlab_rails['db_database'] = '${db_name}'
gitlab_rails['db_username'] = '${db_user}'
gitlab_rails['db_password'] = ENV['GITLAB_DB_PASSWORD']
GITLABCFG

gitlab-ctl reconfigure
