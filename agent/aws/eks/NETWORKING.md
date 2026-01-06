# EKS Networking Requirements for Fargate

## Overview

AWS EKS with Fargate has specific networking requirements that must be met for successful deployment. This document outlines these requirements and how to verify your existing infrastructure meets them.

## Critical Requirements

### For EKS Fargate Deployments

**Private Subnets Only**: EKS Fargate profiles require private subnets. Public subnets will cause deployment failures with the error:
```
InvalidParameterException: Subnet subnet-xxxxx provided in Fargate Profile is not a private subnet
```

### Subnet Requirements Checklist

- [ ] Subnets are **private** (not public)
- [ ] Subnets have **NAT Gateway** for outbound internet access
- [ ] At least **2 subnets** in different availability zones
- [ ] Subnets have sufficient IP addresses (recommend /24 or larger)
- [ ] Subnets are in the same VPC as the EKS cluster
- [ ] Route table has `0.0.0.0/0` pointing to NAT Gateway (not Internet Gateway)

## What Makes a Subnet "Private"?

A private subnet has these characteristics:

1. **No direct Internet Gateway route** - Does not route directly to an Internet Gateway
2. **NAT Gateway route** - Routes to a NAT Gateway for outbound traffic
3. **No public IP assignment** - `map_public_ip_on_launch = false`

## Verifying Your Subnets

### Check if Subnet is Private

```bash
# Replace subnet-xxxxx with your actual subnet ID
SUBNET_ID="subnet-xxxxx"

# Check if subnet assigns public IPs (should be false for private subnets)
aws ec2 describe-subnets --subnet-ids $SUBNET_ID \
  --query 'Subnets[0].MapPublicIpOnLaunch' --output text

# Expected output: False
```

### Check Route Table Configuration

```bash
# Get the route table for your subnet
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query 'RouteTables[0].RouteTableId' --output text)

echo "Route table: $ROUTE_TABLE_ID"

# Check routes - should show NAT Gateway, NOT Internet Gateway
aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]' \
  --output table

# Expected output should show:
# - NatGatewayId: nat-xxxxx
# NOT:
# - GatewayId: igw-xxxxx
```

### Verify NAT Gateway is Healthy

```bash
# Get NAT Gateway ID from route table
NAT_GW_ID=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId' \
  --output text)

# Check NAT Gateway status
aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GW_ID \
  --query 'NatGateways[0].{State:State,PublicIp:NatGatewayAddresses[0].PublicIp}' \
  --output table

# Expected State: available
```

### Check Availability Zones

```bash
# List subnets with their availability zones
aws ec2 describe-subnets \
  --subnet-ids subnet-xxxxx subnet-yyyyy \
  --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}' \
  --output table

# Ensure subnets are in different AZs
```

## Network Architecture

### Recommended Setup (Created by Terraform)

```
VPC (172.5.0.0/16)
│
├── Public Subnet 1 (172.5.0.0/24) [us-east-1a]
│   ├── Internet Gateway ← Routes here
│   └── NAT Gateway 1 (Elastic IP)
│
├── Public Subnet 2 (172.5.1.0/24) [us-east-1b]
│   ├── Internet Gateway ← Routes here
│   └── NAT Gateway 2 (Elastic IP)
│
├── Private Subnet 1 (172.5.2.0/24) [us-east-1a]
│   └── NAT Gateway 1 ← Routes here
│       └── EKS Fargate Pods run here
│
└── Private Subnet 2 (172.5.3.0/24) [us-east-1b]
    └── NAT Gateway 2 ← Routes here
        └── EKS Fargate Pods run here
```

### Route Table Configuration

**Public Subnet Route Table**:
```
Destination      Target
10.0.0.0/16      local
0.0.0.0/0        igw-xxxxx (Internet Gateway)
```

**Private Subnet Route Table**:
```
Destination      Target
10.0.0.0/16      local
0.0.0.0/0        nat-xxxxx (NAT Gateway)
```

## Common Issues and Solutions

### Issue: "Subnet provided in Fargate Profile is not a private subnet"

**Cause**: You're providing public subnets to the Fargate profile.

**Solution**:
1. Verify your subnets are private (see verification steps above)
2. If using existing subnets, ensure they meet all requirements
3. If creating new subnets, use `use_existing_subnet = false` to let Terraform create proper private subnets

### Issue: Pods stuck in "Pending" state

**Cause**: May be due to network connectivity issues or subnet IP exhaustion.

**Solution**:
1. Check NAT Gateway is healthy: `aws ec2 describe-nat-gateways`
2. Verify subnet has available IPs: `aws ec2 describe-subnets --subnet-ids subnet-xxxxx --query 'Subnets[0].AvailableIpAddressCount'`
3. Check Fargate profile status: `aws eks describe-fargate-profile --cluster-name <name> --fargate-profile-name <name>`

### Issue: Pods can't reach internet

**Cause**: NAT Gateway not properly configured or route table misconfigured.

**Solution**:
1. Verify NAT Gateway has an Elastic IP
2. Check route table has correct route to NAT Gateway
3. Verify security groups allow outbound traffic

## Configuration Examples

### Example 1: Let Terraform Create Everything

```hcl
# terraform.tfvars
use_existing_vpc    = false
use_existing_subnet = false
cidr_block         = "172.5.0.0/16"
region             = "us-east-1"
```

This creates:
- VPC with specified CIDR
- 2 public subnets with Internet Gateway
- 2 private subnets with NAT Gateways
- All necessary route tables and associations

### Example 2: Use Existing VPC, Create New Subnets

```hcl
# terraform.tfvars
use_existing_vpc    = true
existing_vpc_id     = "vpc-0123456789abcdef0"
use_existing_subnet = false
cidr_block         = "172.5.0.0/16"  # Must match existing VPC CIDR
region             = "us-east-1"
```

This creates:
- 2 public subnets in your existing VPC
- 2 private subnets in your existing VPC
- NAT Gateways and Elastic IPs
- Route tables for public and private subnets

### Example 3: Use Existing VPC and Existing Private Subnets

```hcl
# terraform.tfvars
use_existing_vpc    = true
existing_vpc_id     = "vpc-0123456789abcdef0"
use_existing_subnet = true
existing_subnet_ids = [
  "subnet-0a1b2c3d4e5f6g7h8",  # Private subnet in us-east-1a
  "subnet-1i2j3k4l5m6n7o8p9"   # Private subnet in us-east-1b
]
region = "us-east-1"
```

**IMPORTANT**: Before using this configuration, verify all subnets meet the requirements listed at the top of this document.

## Troubleshooting Commands

```bash
# Full subnet validation script
SUBNET_ID="subnet-xxxxx"

echo "=== Subnet Details ==="
aws ec2 describe-subnets --subnet-ids $SUBNET_ID \
  --query 'Subnets[0].{SubnetId:SubnetId,VPC:VpcId,AZ:AvailabilityZone,CIDR:CidrBlock,PublicIP:MapPublicIpOnLaunch,AvailableIPs:AvailableIpAddressCount}' \
  --output table

echo -e "\n=== Route Table ==="
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID \
  --query 'RouteTables[0].Routes[*].{Destination:DestinationCidrBlock,Target:GatewayId,NAT:NatGatewayId}' \
  --output table

echo -e "\n=== NAT Gateway Status ==="
NAT_GW_ID=$(aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId' \
  --output text)

if [ ! -z "$NAT_GW_ID" ] && [ "$NAT_GW_ID" != "None" ]; then
  aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GW_ID \
    --query 'NatGateways[0].{State:State,PublicIp:NatGatewayAddresses[0].PublicIp}' \
    --output table
else
  echo "No NAT Gateway found - this is likely a public subnet"
fi

echo -e "\n=== Verdict ==="
PUBLIC_IP=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID \
  --query 'Subnets[0].MapPublicIpOnLaunch' --output text)

if [ "$PUBLIC_IP" == "False" ] && [ ! -z "$NAT_GW_ID" ] && [ "$NAT_GW_ID" != "None" ]; then
  echo "✅ This is a PRIVATE subnet suitable for EKS Fargate"
else
  echo "❌ This is a PUBLIC subnet - NOT suitable for EKS Fargate"
fi
```

## Additional Resources

- [AWS EKS Fargate Documentation](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)
- [VPC and Subnet Sizing](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html)
- [NAT Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [Troubleshooting EKS](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
