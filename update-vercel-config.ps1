# Update vercel.json with current Elastic IP from Terraform
Write-Host "Updating vercel.json with current Elastic IP..." -ForegroundColor Blue

# Change to infra directory to get Terraform outputs
Push-Location "infra"

try {
    # Get the public IP from Terraform output
    $publicIp = terraform output -raw public_ip
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to get Terraform output. Make sure infrastructure is deployed." -ForegroundColor Red
        Pop-Location
        exit 1
    }
    
    Write-Host "Found Elastic IP: $publicIp" -ForegroundColor Green
    
    # Go back to root directory
    Pop-Location
    
    # Read the template file
    $template = Get-Content "vercel.json.template" -Raw
    
    # Replace the placeholder with actual IP
    $updatedContent = $template -replace "{{PUBLIC_IP}}", $publicIp
    
    # Write to vercel.json
    $updatedContent | Set-Content "vercel.json" -NoNewline
    
    Write-Host "vercel.json updated successfully with IP: $publicIp" -ForegroundColor Green
    
    # Show the updated content
    Write-Host "Updated vercel.json content:" -ForegroundColor Yellow
    Get-Content "vercel.json" | Write-Host -ForegroundColor Gray
    
} catch {
    Write-Host "Error updating vercel.json: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
}