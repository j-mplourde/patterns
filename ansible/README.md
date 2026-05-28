# Ansible: deploy via AWS SSM, no SSH, with templated docker-compose

A reference pattern for deploying a containerized app to EC2 hosts where:

- **No SSH keys exist anywhere.** Hosts have no port 22 open; Ansible reaches
  them through AWS Systems Manager Session Manager.
- **Inventory is dynamic.** The `aws_ec2` plugin queries EC2 by tag at runtime,
  so scaling up/down requires zero inventory edits.
- **Secrets come from AWS Secrets Manager**, fetched at deploy time and
  templated into a docker-compose file - never written to disk on the laptop
  running Ansible.
- **A validation playbook runs in CI** to catch docker-compose template errors
  *before* a real deploy can break a real host.

This pairs naturally with the multi-account Terraform pattern in
`../terraform/`: `terraform/modules/server/app` provisions the EC2 host with
the right IAM/tags/log group; this Ansible repo deploys onto it.

---

## Files

```
ansible/
├── ansible.cfg                                 minimal: auto python, /tmp tmpdir
├── group_vars/
│   └── all.yaml                                connection: aws_ssm, become: sudo
├── inventories/
│   └── dev_ca_central_1.aws_ec2.yaml           one per (env, region) - just copy
├── update_app.yaml                             main deploy playbook (CI entry)
├── validate_docker_compose_template.yaml       local render + `docker compose config`
├── requirements.yaml                           ansible-galaxy collections
├── pyproject.toml                              uv deps (boto3, ansible-navigator)
├── roles/
│   └── update_docker_compose/
│       ├── tasks/main.yaml                     the deploy steps
│       └── templates/docker-compose.yaml       the rendered compose file
└── scripts/
    └── log-deployment.sh                       container entrypoint banner
```

Repeat the inventory file per environment+region. The structure is identical;
only the `regions:` list, `filters:`, and the `compose:` variable block change.

---

## Why SSM (not SSH)?

Three reasons:

1. **No bastion, no keypair rotation, no port 22 open to the world.** The
   EC2 host's outbound SSM channel does all the work.
2. **Identity-aware.** Every session is a CloudTrail event (`StartSession`).
   The S3 bucket name in `compose:` (`...-session-manager-logs`) is where the
   keystroke logs land - you can replay what was typed.
3. **Works in private subnets** with no public IP and no NAT (via VPC
   endpoints), so production hosts can sit on a fully private subnet.

Required on each EC2 instance:
- SSM agent (preinstalled on Amazon Linux 2023).
- Instance profile with `AmazonSSMManagedInstanceCore`.
- A `Product=EC2, Service=<project>` tag so the inventory finds it.

All three are set by `terraform/modules/server/app`.

---

## Dynamic inventory (the `aws_ec2` plugin)

`inventories/dev_ca_central_1.aws_ec2.yaml` is the whole config. The plugin
queries EC2 for instances matching the `filters:` block and turns each into an
Ansible host. The `compose:` block lets us turn EC2 tags + facts into
Ansible variables - so a deployment-time value like `hostname` or
`log_group_name` either comes straight from the inventory file or from an EC2
tag - never from a hand-edited host list.

```yaml
plugin: aws_ec2
use_ssm_inventory: true
regions: [ca-central-1]
filters:
  tag:Product: EC2
  tag:Service: orbit
compose:
  app_environment: "'dev'"
  hostname:        "'dev.orbitapp.example.com'"
  log_group_name:  tags.LogGroup   # straight from the EC2 tag
```

---

## The role: `update_docker_compose`

The single role is the entire deploy. It:

1. Gathers EC2 metadata (region, instance id).
2. Pulls **two** secrets from Secrets Manager: `orbit/app` (managed) and
   `orbit/app_unmanaged` (third-party API keys etc.). Keeping these split
   means the managed secrets can be rotated by Terraform without humans
   touching them.
3. Writes a small `log-deployment.sh` shim that every container will use as
   its entrypoint.
4. Templates `docker-compose.yaml` to `/app/docker-compose.yaml`, substituting
   the secrets and inventory vars.
5. **Snapshots the previous deploy tag** before overwriting `/app/deployment-info`,
   so the new compose file knows what *used* to be running (audit trail and
   instant rollback context).
6. `docker compose pull` and `docker compose up -d --wait`.
7. `docker image prune -af`.

---

## The compose template + entrypoint shim

The template is a Jinja2 file rendered by Ansible. Notable patterns:

- **YAML anchors (`x-…`)** for service defaults, AWS logging driver, Traefik
  args, and shared environment - so every service inherits the same baseline.
- **Traefik for TLS.** Labels on each service define the routing rule; Traefik
  fetches Let's Encrypt certs over the HTTP-01 challenge. No nginx config.
- **Container entrypoint banner.** Every container is started via
  `/app/scripts/log-deployment.sh "<real command>"`. That shim reads
  `/app/deployment-info` (written by Ansible right before the restart) and
  emits a single JSON line to stdout, so CloudWatch logs always answer "what
  tag is this container running?" at the top of every log stream.
- **Two networks.** `app` for ingress-facing services (Traefik, frontend,
  backend), `server_side` for internal services (Redis, workers). Backend
  bridges both.

---

## Validation playbook (`validate_docker_compose_template.yaml`)

Runs on `localhost` only. Renders the docker-compose template with mock
variables and pipes the result through `docker compose config --quiet` to
validate YAML + compose schema. CI runs this on every PR that touches the
template - the cheapest possible safety net against "I forgot a closing brace,
prod restarts, container fails to come up, rollback is manual" incidents.

---

## CI entry point

```sh
uv sync
uv run ansible-galaxy install -r requirements.yaml

aws sso login --sso-session acme && export AWS_PROFILE=<profile>

uv run ansible-playbook \
  -i inventories/dev_ca_central_1.aws_ec2.yaml \
  update_app.yaml \
  -e image_tag=$VERSION
```

`$VERSION` is the ECR image tag (usually the short commit SHA for `dev`, or a
semver release tag for `qa`/`prod`).
