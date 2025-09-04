******IaC Implementation******

**Repositoey: si-iac-challenge**

This document contains a complete, step-by-step implementation of the IaC challenge. 
It includes:

	1. Terraform code to provision an API Gateway (HTTP API), Lambda function, S3 bucket, IAM roles & policies, 
     CloudWatch dashboard & alarms, and minimal observability resources.
	2. A small Python Lambda that lists objects in the S3 bucket.
	3. A sample GitHub Actions CI/CD workflow (plan on PR, manual approval applies on merge to main) with security scans (tfsec/checkov).
	4. Explanations of how rollback, validation, monitoring and security hardening work

This repository is designed to be run locally or from a CI runner (GitHub Actions). The Terraform flow uses a local archive file built for the Lambda. 
CI runs will build that artifact inside the runner.

**High-level design — how this satisfies the brief**

_Application:_ API Gateway -> Lambda -> lists contents of an S3 bucket.

_Scalability:_ Lambda + HTTP API autoscale automatically. S3 scales transparently.

_Security / least-privilege:_ Lambda role only has s3:ListBucket and s3:GetObject on the 
specific bucket, plus minimal CloudWatch logging permissions.
                              
_Observability:_ Lambda tracing (X-Ray), CloudWatch Logs (with retention), CloudWatch Dashboard summarising Invocations & Errors, 
CloudWatch alarm wired to an SNS topic for actionable alerts.

_CI/CD:_ GitHub Actions (PR plan + security scans; protected production environment for applying). 
Terraform state should be stored in an S3 backend with a DynamoDB lock table (a backend example is included).

**Step-by-step: how to run locally**

**Prerequisites:**

	•	AWS credentials configured (CLI profile or env vars).
	•	Terraform installed (>= 1.3)
	•	GitHub Actions: create repo secrets for production deploy (see README in repo)

**Architectural Diagram**
<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/f8003a6c-c285-4ce1-90c2-8f3cfa375a95" />

**Commands (run from repo root):**

	1.	cd terraform
	2.	terraform init  # or use backend config to point to your S3 backend
	3.	terraform apply (accept plan) — this will package ../lambda as a zip, create resources and output the API endpoint.

After "terraform apply" completes, the api_endpoint output contains the URL. GET that URL to invoke the Lambda, which returns the list of objects in the bucket.

**Explanation/justification - GitHub Actions:**

	•	PR runs plan + security scans (tfsec). That provides validation and prevents insecure or misconfigured infra from being merged.
	•	apply runs only on main and uses a protected production environment — GitHub environments support required reviewers and checks which implement a manual approval gate (this satisfies the requirement for 				approval & rollback control).

**CI/CD: Rollback & Validation strategy**

**Validation (pre-deploy / PR):**

	•	terraform validate, terraform fmt (style), tfsec (security), optional checkov and tflint.
	•	Integration tests (optional): run a small integration harness that calls the API endpoint in a staging environment.

**Apply & Approval:**

	•	Protect the production environment in GitHub. Require at least one approver before the apply job runs.
	•	Apply uses the previously generated tfplan artifact (so the exact planned change is applied).

**Rollback:**

	•	Terraform state is the source of truth. If a deploy causes a regression, rollback is done by checking out the previous commit (the last known good), re-running the pipeline (which will create a plan that 			returns infra to the previous state) and applying that plan.
	•	Additionally: enable S3 backend versioning and keep copies of the state file; Terraform Cloud (if you choose) or S3 versioning retains prior states so you can restore to a previous state if needed.

**Observability & Alerting**

**Implemented in this submission (Terraform resources):**

	•	Lambda tracing: tracing_config { mode = "Active" } (X-Ray).
	•	CloudWatch Log Group with retention.
	•	CloudWatch Dashboard showing Lambda Invocations & Errors.
	•	CloudWatch alarm on Lambda Errors that triggers an SNS topic.

**Operational monitoring recommendations (additional):**

	•	Use CloudWatch Logs Insights for searching and creating more refined alerts.
	•	Use AWS X-Ray sampling and traces; integrate traces with the dashboard to find the root cause.
	•	Consider a 3rd-party APM (Datadog/NewRelic) for distributed tracing across services.
	•	Configure API Gateway access logs to a dedicated log group (not included by default in the minimal TF here; add access_log_settings to the stage if desired).

**Actionable vs. noisy alerts:**

	•	Actionable: Lambda error rate > 1 in 5 minutes, or sustained increase in latency (p95 > threshold) — these are alarms in Terraform.
	•	Noisy: Single transient errors and minor cold-start spikes — avoid alarming on 1 datapoint/1 minute for non-critical metrics. Use aggregation (e.g., evaluation_periods = 3 with period = 300) and use anomaly 			detection where appropriate.
	•	Use alert suppression and on-call escalation rules (SNS -> PagerDuty) to avoid pager fatigue.


****Security considerations**** (what was implemented + recommendations)

****Implemented/considered in the code:****

	•	S3 bucket defaulted to private, with public access block and server-side encryption (SSE-S3).
	•	Lambda IAM role uses least privilege (only ListBucket/GetObject on the target bucket + logging & X-Ray perms).
	•	CloudWatch Log retention is set (to avoid indefinite log retention).
	•	CI pipeline includes tfsec security scanning as a gate.

****Recommended additional hardening:****

	•	Use KMS-managed CMKs to encrypt sensitive resources (S3 bucket and state), and enable key rotation.
	•	Put Terraform state in S3 with DynamoDB locking and S3 encryption + bucket policy to restrict access.
	•	Enable AWS Config, GuardDuty, and IAM Access Analyser to detect drift and suspicious activity.
	•	Enable VPC endpoints for S3 and other services to restrict the traffic path when integrating with VPC resources.
	•	Use WAF in front of API Gateway to protect against common web attacks.
	•	Add CI scanning (checkov, tflint, kics) and secret scanning (GitHub secret scanning / pre-commit hooks) to prevent secrets leaking.
	•	Run a privileged IAM review and rotate any long-lived credentials; prefer short-lived roles via OIDC for CI.

 





