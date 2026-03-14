# AWS Multi-Region Assessment — Unleash Live

A multi-region AWS infrastructure deployment using Terraform, featuring API Gateway, Lambda, DynamoDB, ECS Fargate, and Cognito authentication.

---

## Architecture Overview
```
                        ┌─────────────────────────┐
                        │   Amazon Cognito         │
                        │   User Pool (us-east-1)  │
                        │   [Centralized Auth]      │
                        └────────────┬────────────┘
                                     │ JWT Authorizer
               ┌─────────────────────┴─────────────────────┐
               │                                           │
   ┌───────────▼──────────┐                 ┌─────────────▼──────────┐
   │   us-east-1          │                 │   eu-west-1            │
   │                      │                 │                        │
   │  API Gateway         │                 │  API Gateway           │
   │  ├── /greet          │                 │  ├── /greet            │
   │  └── /dispatch       │                 │  └── /dispatch         │
   │                      │                 │                        │
   │  Lambda (Greeter)    │                 │  Lambda (Greeter)      │
   │  Lambda (Dispatcher) │                 │  Lambda (Dispatcher)   │
   │  DynamoDB            │                 │  DynamoDB              │
   │  ECS Fargate         │                 │  ECS Fargate           │
   └──────────────────────┘                 └────────────────────────┘
```

---

## Repository Structure
```
aws-assessment/
├── auth/                        # Cognito User Pool (us-east-1 only)
│   └── main.tf
├── modules/
│   └── compute/                 # Reusable module deployed in both regions
│       ├── main.tf              # Lambda, API GW, DynamoDB, ECS, VPC
│       ├── variables.tf
│       └── outputs.tf
├── envs/
│   ├── us-east-1/               # Calls compute module for us-east-1
│   │   └── main.tf
│   └── eu-west-1/               # Calls compute module for eu-west-1
│       └── main.tf
├── test_script.py               # Automated test script
├── .github/
│   └── workflows/
│       └── deploy.yml           # CI/CD pipeline
└── README.md
```

---

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured
- Python 3.x
- pip packages: `requests`, `boto3`

---

## How to Deploy

### 1. Clone the Repo
```bash
git clone https://github.com/Anurag-init6/aws-assessment
cd aws-assessment
```

### 2. Deploy Cognito Auth (us-east-1 only)
```bash
cd auth
terraform init
terraform apply -auto-approve

# Note these outputs — needed for next steps
terraform output user_pool_id
terraform output user_pool_client_id
```

### 3. Reset Cognito Test User Password
```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id <user_pool_id_from_above> \
  --username <your_email> \
  --password "YourNewPassword123!" \
  --permanent \
  --region us-east-1
```

### 4. Deploy Compute Stack — us-east-1
```bash
cd ../envs/us-east-1
terraform init
terraform apply -auto-approve

# Note the API URL output
terraform output api_url_us
```

### 5. Deploy Compute Stack — eu-west-1
```bash
cd ../envs/eu-west-1
terraform init
terraform apply -auto-approve

# Note the API URL output
terraform output api_url_eu
```

---

## How to Run the Test Script

### Install Dependencies
```bash
pip install requests boto3 --break-system-packages
# or using virtual env:
python3 -m venv ~/venv && source ~/venv/bin/activate
pip install requests boto3
```

### Fill in Variables in test_script.py

Open `test_script.py` and set:
- `USER_POOL_ID` — from auth terraform output
- `CLIENT_ID` — from auth terraform output
- `USERNAME` — your email
- `PASSWORD` — password set in Step 3
- `API_URL_US` — from envs/us-east-1 terraform output
- `API_URL_EU` — from envs/eu-west-1 terraform output

### Run
```bash
python3 test_script.py
```

### Expected Output
```
🔐 Getting JWT from Cognito...
✅ JWT obtained
🚀 Calling /greet in both regions concurrently...
[US /greet]    Status: 200 | Latency: ~1300ms | Region check: ✅ PASS
[EU /greet]    Status: 200 | Latency: ~1900ms | Region check: ✅ PASS
[US /dispatch] Status: 200 | Latency: ~1900ms | Region check: ✅ PASS
[EU /dispatch] Status: 200 | Latency: ~4500ms | Region check: ✅ PASS
✅ All calls complete!
```

> Note: EU latency is higher than US — this demonstrates real geographic performance difference.

---

## Multi-Region Provider Structure

The key design decision is a **single reusable Terraform module** (`modules/compute/`) that is called twice — once per region — with different `region` variables:
```hcl
# envs/us-east-1/main.tf
module "compute" {
  source = "../../modules/compute"
  region = "us-east-1"
  ...
}

# envs/eu-west-1/main.tf
module "compute" {
  source = "../../modules/compute"
  region = "eu-west-1"
  ...
}
```

**Cognito stays centralized in us-east-1.** Both regions' API Gateways use a JWT authorizer pointing to the same Cognito User Pool. The auth stack outputs (`user_pool_id`, `client_id`) are read by each env via `terraform_remote_state`.

**ECS Fargate uses public subnets** (no NAT Gateway) to avoid unnecessary data transfer costs while still allowing the container to reach the SNS endpoint.

---

## Tear Down

Run in this order to avoid dependency errors:
```bash
cd envs/eu-west-1 && terraform destroy -auto-approve
cd ../us-east-1   && terraform destroy -auto-approve
cd ../../auth     && terraform destroy -auto-approve
```

---

## CI/CD Pipeline

The `.github/workflows/deploy.yml` defines four automated stages:

| Stage | Tool | Purpose |
|---|---|---|
| Lint/Validate | `terraform fmt`, `terraform validate` | Check formatting and syntax |
| Security Scan | `tfsec` | Detect IAM/security misconfigurations |
| Plan | `terraform plan` | Preview infrastructure changes |
| Test Placeholder | `python3 test_script.py` | Run automated tests post-deploy |


