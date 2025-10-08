#!/bin/bash
# Update vercel.json with current Elastic IP from Terraform

echo "🔄 Updating vercel.json with current Elastic IP..."

# Change to infra directory to get Terraform outputs
cd infra

# Get the public IP from Terraform output
PUBLIC_IP=$(terraform output -raw public_ip)

if [ $? -ne 0 ]; then
    echo "❌ Failed to get Terraform output. Make sure infrastructure is deployed."
    exit 1
fi

echo "📍 Found Elastic IP: $PUBLIC_IP"

# Go back to root directory
cd ..

# Read the template file and replace placeholder
sed "s/{{PUBLIC_IP}}/$PUBLIC_IP/g" vercel.json.template > vercel.json

echo "✅ vercel.json updated successfully with IP: $PUBLIC_IP"

# Show the updated content
echo "📄 Updated vercel.json content:"
cat vercel.json