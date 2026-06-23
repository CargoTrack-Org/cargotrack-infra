$region  = "us-east-1"
$account = "692828329130"
$project = "cargotrack"

Write-Host "=== CargoTrack Pre-Apply Cleanup ===" -ForegroundColor Cyan

# 1. Secrets Manager
Write-Host "[1/8] Secrets Manager..." -ForegroundColor Yellow
aws secretsmanager delete-secret --secret-id "cargotrack-database-secret-v2" --force-delete-without-recovery --region $region 2>$null
aws secretsmanager delete-secret --secret-id "cargotrack-application-secret-v2" --force-delete-without-recovery --region $region 2>$null
Write-Host "  done" -ForegroundColor Green

# 2. SQS Queues
Write-Host "[2/8] SQS Queues..." -ForegroundColor Yellow
aws sqs delete-queue --queue-url "https://sqs.$region.amazonaws.com/$account/cargotrack-compliance-trigger-dlq" --region $region 2>$null
aws sqs delete-queue --queue-url "https://sqs.$region.amazonaws.com/$account/cargotrack-compliance-trigger" --region $region 2>$null
Write-Host "  done" -ForegroundColor Green

# 3. KMS Alias
Write-Host "[3/8] KMS Alias..." -ForegroundColor Yellow
aws kms delete-alias --alias-name "alias/cargotrack-cmk" --region $region 2>$null
Write-Host "  done" -ForegroundColor Green

# 4. DynamoDB
Write-Host "[4/8] DynamoDB table..." -ForegroundColor Yellow
aws dynamodb delete-table --table-name "cargotrack-audit" --region $region 2>$null
Start-Sleep -Seconds 10
Write-Host "  done" -ForegroundColor Green

# 5. EventBridge
Write-Host "[5/8] EventBridge bus..." -ForegroundColor Yellow
aws events delete-event-bus --name "cargotrack-events" --region $region 2>$null
Write-Host "  done" -ForegroundColor Green

# 6. RDS Subnet Group
Write-Host "[6/8] RDS subnet group..." -ForegroundColor Yellow
aws rds delete-db-subnet-group --db-subnet-group-name "cargotrack-db-subnet-group" --region $region 2>$null
Write-Host "  done" -ForegroundColor Green

# 7. IAM Roles
Write-Host "[7/8] IAM roles..." -ForegroundColor Yellow

$clusterPolicies = @(
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
)
foreach ($p in $clusterPolicies) {
    aws iam detach-role-policy --role-name "cargotrack-eks-cluster-role" --policy-arn $p 2>$null
}
$inlinePolicies = (aws iam list-role-policies --role-name "cargotrack-eks-cluster-role" --query "PolicyNames" --output text 2>$null) -split "`t"
foreach ($p in $inlinePolicies) { if ($p -and $p.Trim() -ne "") { aws iam delete-role-policy --role-name "cargotrack-eks-cluster-role" --policy-name $p.Trim() 2>$null } }
aws iam delete-role --role-name "cargotrack-eks-cluster-role" 2>$null

$nodePolicies = @(
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
)
foreach ($p in $nodePolicies) {
    aws iam detach-role-policy --role-name "cargotrack-eks-node-role" --policy-arn $p 2>$null
}
$inlinePolicies = (aws iam list-role-policies --role-name "cargotrack-eks-node-role" --query "PolicyNames" --output text 2>$null) -split "`t"
foreach ($p in $inlinePolicies) { if ($p -and $p.Trim() -ne "") { aws iam delete-role-policy --role-name "cargotrack-eks-node-role" --policy-name $p.Trim() 2>$null } }
aws iam delete-role --role-name "cargotrack-eks-node-role" 2>$null
Write-Host "  done" -ForegroundColor Green

# 7b. IRSA Roles — must delete inline policies first, then the role
Write-Host "[7b/8] IRSA roles..." -ForegroundColor Yellow
$irsaRoles = @(
    "cargotrack-irsa-core-service",
    "cargotrack-irsa-document-service",
    "cargotrack-irsa-ai-service",
    "cargotrack-irsa-alb-controller",
    "cargotrack-irsa-cluster-autoscaler",
    "cargotrack-irsa-eso"
)
foreach ($r in $irsaRoles) {
    $policies = (aws iam list-role-policies --role-name $r --query "PolicyNames" --output text 2>$null) -split "`t"
    foreach ($p in $policies) {
        if ($p -and $p.Trim() -ne "") {
            aws iam delete-role-policy --role-name $r --policy-name $p.Trim() 2>$null
        }
    }
    aws iam delete-role --role-name $r 2>$null
}
Write-Host "  done" -ForegroundColor Green

# 8. Legacy SSM Parameters
Write-Host "[8/8] SSM parameters..." -ForegroundColor Yellow
aws ssm delete-parameter --name "/cargotrack/database/name" --region $region 2>$null
aws ssm delete-parameter --name "/cargotrack/database/host" --region $region 2>$null
aws ssm delete-parameter --name "/cargotrack/database/user" --region $region 2>$null
aws ssm delete-parameter --name "/cargotrack/database/port" --region $region 2>$null
aws ssm delete-parameter --name "/cargotrack/application/node-env" --region $region 2>$null
Write-Host "  done" -ForegroundColor Green

# SQS cooldown
Write-Host "Waiting 65s for SQS cooldown..." -ForegroundColor Yellow
Start-Sleep -Seconds 65

Write-Host "=== Cleanup complete. Run: terraform apply ===" -ForegroundColor Cyan
