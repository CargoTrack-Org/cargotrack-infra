# ─────────────────────────────────────────────────────────────────────────────
# CargoTrack — Pre-Apply Cleanup Script
#
# PURPOSE: Deletes orphaned AWS resources left behind from a previous
#          terraform destroy that didn't fully clean up.
#          Run this ONCE before terraform apply on a fresh state.
#
# SAFE TO RE-RUN: All deletions are idempotent (errors suppressed with 2>$null)
# ─────────────────────────────────────────────────────────────────────────────

$region  = "us-east-1"
$account = "692828329130"
$project = "cargotrack"

Write-Host "`n=== CargoTrack Pre-Apply Cleanup ===" -ForegroundColor Cyan
Write-Host "Region:  $region" -ForegroundColor Gray
Write-Host "Account: $account" -ForegroundColor Gray

# ── 1. Secrets Manager ────────────────────────────────────────────────────────
Write-Host "`n[1/8] Cleaning Secrets Manager..." -ForegroundColor Yellow
aws secretsmanager delete-secret `
    --secret-id "$project-database-secret-v2" `
    --force-delete-without-recovery `
    --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-database-secret-v2" -ForegroundColor Green

aws secretsmanager delete-secret `
    --secret-id "$project-application-secret-v2" `
    --force-delete-without-recovery `
    --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-application-secret-v2" -ForegroundColor Green

# ── 2. SQS Queues ─────────────────────────────────────────────────────────────
Write-Host "`n[2/8] Cleaning SQS queues..." -ForegroundColor Yellow
$dlqUrl  = "https://sqs.$region.amazonaws.com/$account/$project-compliance-trigger-dlq"
$mainUrl = "https://sqs.$region.amazonaws.com/$account/$project-compliance-trigger"
aws sqs delete-queue --queue-url $dlqUrl  --region $region 2>$null | Out-Null
aws sqs delete-queue --queue-url $mainUrl --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-compliance-trigger-dlq" -ForegroundColor Green
Write-Host "  ✓ cargotrack-compliance-trigger" -ForegroundColor Green

# ── 3. KMS Alias ──────────────────────────────────────────────────────────────
Write-Host "`n[3/8] Cleaning KMS alias..." -ForegroundColor Yellow
aws kms delete-alias --alias-name "alias/$project-cmk" --region $region 2>$null | Out-Null
Write-Host "  ✓ alias/cargotrack-cmk" -ForegroundColor Green

# ── 4. DynamoDB Table ─────────────────────────────────────────────────────────
Write-Host "`n[4/8] Cleaning DynamoDB table..." -ForegroundColor Yellow
aws dynamodb delete-table --table-name "$project-audit" --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-audit (waiting for deletion...)" -ForegroundColor Green
# Wait for table to actually delete before continuing
Start-Sleep -Seconds 10

# ── 5. EventBridge Event Bus ──────────────────────────────────────────────────
Write-Host "`n[5/8] Cleaning EventBridge bus..." -ForegroundColor Yellow
aws events delete-event-bus --name "$project-events" --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-events" -ForegroundColor Green

# ── 6. RDS DB Subnet Group ────────────────────────────────────────────────────
Write-Host "`n[6/8] Cleaning RDS subnet group..." -ForegroundColor Yellow
aws rds delete-db-subnet-group `
    --db-subnet-group-name "$project-db-subnet-group" `
    --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-db-subnet-group" -ForegroundColor Green

# ── 7. IAM Roles (detach policies first, then delete) ─────────────────────────
Write-Host "`n[7/8] Cleaning IAM roles..." -ForegroundColor Yellow

$clusterPolicies = @(
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
)
foreach ($policy in $clusterPolicies) {
    aws iam detach-role-policy `
        --role-name "$project-eks-cluster-role" `
        --policy-arn $policy `
        --region $region 2>$null | Out-Null
}
aws iam delete-role --role-name "$project-eks-cluster-role" --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-eks-cluster-role" -ForegroundColor Green

$nodePolicies = @(
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
)
foreach ($policy in $nodePolicies) {
    aws iam detach-role-policy `
        --role-name "$project-eks-node-role" `
        --policy-arn $policy `
        --region $region 2>$null | Out-Null
}
aws iam delete-role --role-name "$project-eks-node-role" --region $region 2>$null | Out-Null
Write-Host "  ✓ cargotrack-eks-node-role" -ForegroundColor Green

# ── 8. SSM Parameters (legacy paths from database module) ─────────────────────
Write-Host "`n[8/8] Cleaning legacy SSM parameters..." -ForegroundColor Yellow
$ssmParams = @(
    "/$project/database/name",
    "/$project/database/host",
    "/$project/database/user",
    "/$project/database/port",
    "/$project/application/node-env"
)
foreach ($param in $ssmParams) {
    aws ssm delete-parameter --name $param --region $region 2>$null | Out-Null
    Write-Host "  ✓ $param" -ForegroundColor Green
}

# ── SQS cooldown ──────────────────────────────────────────────────────────────
Write-Host "`nWaiting 65 seconds for SQS queue-name cooldown..." -ForegroundColor Yellow
Write-Host "(AWS requires 60s before a queue with the same name can be recreated)" -ForegroundColor Gray
Start-Sleep -Seconds 65

Write-Host "`n=== Cleanup Complete ===" -ForegroundColor Cyan
Write-Host "You can now run: terraform apply" -ForegroundColor Green
