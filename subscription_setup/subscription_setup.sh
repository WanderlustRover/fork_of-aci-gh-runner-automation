#!/bin/bash

# This Azure CLI script helps prepare everything you need to run Terraform
# in GitHub Actions. It Sets up:

    # Create 
    # Security Group for RBAC Assignment at Subscription scope
    # Application Registration and Service Principal to place in said Group
    # RG, Storage Account, and Container to store Terraform State remotely.

    # Please change the variables to suit your requirements! 

# Pre-requisites 
#
# Ownership of:
# An Azure Tenant/Entra ID
# Azure Subscription, preferrably one dedicated to core infrastructure 
# GitHub Account 
# GitHub Repo dedicated to your Azure Tenant Administration 
# AzureCLI Installed 



################################################################################
#
# Set the below values which have x's in them
# the other values can be modified if desired, though not essential
# 
################################################################################

export rootGH="xxxxxxxxxxxxxxx"                       # GitHub Org or User Name
export adminRepo="xxxxxxxxxxxxxxxxxx"                 # Core Azure Admin Repo Name
export branch1="xxxx"                                 # Primary Branch for OIDC Config

export tenant="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # Tenant id
export coreSub="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # Core Subscription ID
export location="xxxxxxx"                             # RG and Storage Account region

export coresub_owner_group_name="coresub_owners"      # Entra Group for Owner Role
export repoFullName="${rootGH}/${adminRepo}"          # Full Core Azure Admin Repo Name
export rgname="rg-terraform-core-$location"           # RG name 
export storage_account_name="coreterraform$location"  # Note this must be unique!
export container_name="coretfstate"                   # Container name.
export tfstate_delete_lock_name="delete_lock_tfstate" # Name of delete lock
export initTag="usage=tfstate managed_by=az_cli"      # Tag on RG & SA 

col1_width=20 
col2_width=40 
echo "-------------------------------------------------------------------"
printf "| %-*s | %-*s |\n" $col1_width "Variable Name" $col2_width "Value" 
echo "-------------------------------------------------------------------"
printf "| %-*s | %-*s |\n" $col1_width "rootGH" $col2_width "$rootGH" 
printf "| %-*s | %-*s |\n" $col1_width "adminRepo" $col2_width "$adminRepo" 
printf "| %-*s | %-*s |\n" $col1_width "branch1" $col2_width "$branch1" 
printf "| %-*s | %-*s |\n" $col1_width "repoFullName" $col2_width "$repoFullName" 
printf "| %-*s | %-*s |\n" $col1_width "tenant" $col2_width "$tenant" 
printf "| %-*s | %-*s |\n" $col1_width "coreSub" $col2_width "$coreSub" 
printf "| %-*s | %-*s |\n" $col1_width "location" $col2_width "$location" 
printf "| %-*s | %-*s |\n" $col1_width "rgname" $col2_width "$rgname" 
printf "| %-*s | %-*s |\n" $col1_width "storage_account_name" $col2_width "$storage_account_name" 
printf "| %-*s | %-*s |\n" $col1_width "container_name" $col2_width "$container_name" 
printf "| %-*s | %-*s |\n" $col1_width "initTag" $col2_width "$initTag" 
echo "-------------------------------------------------------------------"


# Pause the script, awaiting a single key press to continue
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""


################################################################################
#
# Login to Azure to start its parts
#
################################################################################

az logout
az login --tenant $tenant

# Get the Display name of CoreSub"
coreSubName=$(
    az account list \
    --query "[?id=='$coreSub'].name" \
    --output tsv
)
echo "The coreSubName is $coreSubName"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""

################################################################################
#
# Create Foundational Entra ID Management Group and Identity 
#
################################################################################

# Create Security Group to place Owners of Foundational/Core Subscription
owner_group_id=$(
    az ad group create \
        --display-name "$coresub_owner_group_name" \
        --mail-nickname "$coresub_owner_group_name" \
        --description "Members to have Owner Role over coreadminsub" \
        --force false \
        --query id \
        --output tsv
)
echo "Security Group created with objectID: $owner_group_id"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""


# Create an Application Registration 
# Get the appId
appId=$(
    az ad app create \
        --display-name "app-reg-gha-$repoFullName" \
        --query appId \
        --output tsv
) 
echo "Application Registration created with application/client ID: $appId"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""
# Get the objId
appreg_objId=$(
    az ad app show \
        --id $appId \
        --query id \
        --output tsv
) 
echo "Application Registration's objectId: $appreg_objId"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""
# Set the owner of the Application Registration to be the 
# currently signed in user who is executing this script
az ad app owner add --$appId \
    --owner-object-id $(
        az ad signed-in-user show \
            --query id \
            --output tsv
    )
echo "The currently signed in user is now Owner of $appId"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""

# Create Federated Identity Credential
# Note, this is using a Branch
# The safer route if your GitHub repository supports it, is to use Environment
# Environments allow to leverage Environmental protection rules
cat <<EOF > credential.json
{
    "name": "oidc_for_core_azure_admin",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:$repoFullName:ref:refs/heads/$branch1",
    "description": "OIDC for $rootGH to manage their Azure Tenant via GHA in $adminRepo",
    "audiences": [
        "api://AzureADTokenExchange"
    ]
}
EOF
echo "Federated GitHub Credential .json file created."
echo "This file is located in the directory where this script is running."
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""


# Update the App Registration with the OIDC Federation to the GitHub Repo
az ad app federated-credential create \
    --id $appId \
    --parameters credential.json
rm -f credential.json
echo "Federated GitHub Credential added to $appId"
echo "The credential.json file has also been removed."
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""


# RBAC is best done by Security Groups being the assigned identity to the scope
# Members of the Security Group inherit its RBAC
# Application Registrations cannot be added to Security Groups
# Service Principal can be added to Security Groups
# Create a Service Principal for that App Registraiton
servicePrincipalId=$(\
    az ad sp create \
        --id $appId \
        --query id \
        --output tsv
)
echo "Service Principal made for $appId with objectId:$servicePrincipalId"  
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""


# Add Service Principal to the Security Group  
az ad group member add \
    --group $coresub_owner_group_name \
    --member-id $servicePrincipalId
wait
echo "Service Principal $servicePrincipalId added as member to group"  
echo "$coresub_owner_group_name with objectId $owner_group_id."
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""


# Assign Owner Role to the Owner Security Group @ Foundational/Core Subscription
# https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-cli
# Also note the scope syntax may have errors depending on version 
# https://learn.microsoft.com/en-us/answers/questions/1360676/the-request-did-not-have-a-subscription-or-a-valid  
az role assignment create \
    --role "Owner" \
    --assignee "$owner_group_id" \
    --scope "subscriptions/$coreSub" 
echo "Security Group $coresub_owner_group_name assigned the Owner role"
echo "to Subscription $coreSubName."
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""



################################################################################
#
# Set Up GitHub Repo 
#
################################################################################

# Output the values to input to the Admin Repo as GitHub Secrets
echo -e "Create GitHub Repo Secrets for Service Principal"
echo ""  
echo -e "ARM_CLIENT_ID: $appId"
echo -e "ARM_TENANT_ID: $tenant"
echo -e "ARM_SUBSCRIPTION_ID: $coreSub"  
echo ""  
echo ""    

# Open browser to the secret settings of the repo, to input values
start https://github.com/$repoFullName/settings/secrets/
echo "The Secrets page of the Repo has been opened in a browser to be updated"
echo "with the above values. Note that the ARM_CLIENT_ID is the applicationID"
echo "which is shared between"
echo "the Application Registration (objID:$appId)"   
echo "and"
echo "the Service Principal (objID:$servicePrincipalId)"   
echo ""  
echo ""    
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""


################################################################################
#
# Create Foundational Terraform State Remote Azure Backend 
#
################################################################################

# Setting the Subscription shouldn't be necessary due it being set at LogIn
#az account set \
#    --subscription $coreSub
#echo "Set subscription to $coreSubName / $coreSub"
#read -r -n 1 -s "Press any key to continue..."
#echo "Continuing..."  
#echo ""  

# Create Resource Group to house the Terraform Backend
az group create \
    --location $location \
    --name $rgname \
    --tags "$initTag"  
wait  
echo "Resource Group created: $rgname"  
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""

# Create Storage account to store Terraform State  
az storage account create \
    --location $location \
    --resource-group $rgname \
    --name $storage_account_name \
    --tags "$initTag" \
    --https-only \
    --sku Standard_LRS \
    --encryption-services blob \
    --subscription $coreSub  
wait  
echo "Storage Account created in $rgname: $storage_account_name"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo "" 

# Lock the storage account so that it, and therefore the Terraform State
# cannot be deleted by accident.
az lock create \
    --name $tfstate_delete_lock_name \
    --lock-type CanNotDelete \
    --resource-group $rgname \
    --resource-name $storage_account_name \
    --resource-type Microsoft.Storage/storageAccounts  
wait  
echo "DeleteLock created on $storage_account_name"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""

# Create the exact container for the Terraform Statefile
container_id=$(
    az storage container create \
        --name $container_name \
        --account-name $storage_account_name \
        --public-access off \
        --query "id" \
        --output tsv
) 
wait  
echo "Container created for Terraform Backend: $storage_account_name / $container_name"
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""

# Grant the SP the required role to edit the contents so it can store
# the Terraform State 
az role assignment create \
    --assignee "$servicePrincipalId" \
    --scope "$container_id" \
    --role "Storage Blob Data Contributor" 
wait  
echo "$servicePrincipalId assigned Storage Blob Data Contributor at $container_name" 
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""

################################################################################
#
# Update Terraform State Remote Azure Backend Code
#
################################################################################

echo -e ""
echo -e ""
echo -e "Storage account details needed for Terraform Backend Configuration:"
echo -e "Resource Group: $rgname"
echo -e "Storage Account: $storage_account_name"
echo -e "Container Name: $container_name"
echo -e ""
read -n 1 -s -r -p "Press any key to continue..."
echo "Continuing..."
echo ""

################################################################################
#
# Set Up GitHub Action Workflows 
#
################################################################################

# Use Azure Login action with OIDC 
# ``` 
# name: Run Azure Login with OIDC
# # Define the triggers for the workflow
# on: 
#   push:
#       branches:
#           - main
#   # Allow manual dispatch of the workflow
#   workflow_dispatch:
# 
# permissions:
#   id-token: write
#   contents: read
# jobs:
#   build-and-deploy:
#     runs-on: ubuntu-latest
# 
#     steps:
#       # Login to Azure     
#       - name: 'Az CLI login'
#         uses: azure/login@v1
#         with:
#           client-id: ${{ secrets.AZURE_CLIENT_ID }}
#           tenant-id: ${{ secrets.AZURE_TENANT_ID }}
#           subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
# 
#       - name: 'Run az commands'
#         run: |
#           az account show
#           az group list
# ```


# https://learn.microsoft.com/en-us/azure/developer/github/#connect-from-azure-openid-connect 
# https://docs.github.com/en/actions/security-for-github-actions/#security-hardening-your-deployments/configuring-openid-connect-in-azure 


col0_width=63 
col1_width=21 
col2_width=40 
echo "-------------------------------------------------------------------"
printf "| %-*s |\n" $col0_width "Components Used Summary" 
echo "-------------------------------------------------------------------"
printf "| %-*s | %-*s |\n" $col1_width "Variable Name" $col2_width "Value" 
echo "-------------------------------------------------------------------"
printf "| %-*s | %-*s |\n" $col1_width "GitHub Org/User" $col2_width "$rootGH" 
printf "| %-*s | %-*s |\n" $col1_width "GitHub Repo" $col2_width "$adminRepo" 
printf "| %-*s | %-*s |\n" $col1_width "Primary Branch" $col2_width "$branch1" 
printf "| %-*s | %-*s |\n" $col1_width "Full GitHub Repo" $col2_width "$repoFullName" 
printf "| %-*s | %-*s |\n" $col1_width "Azure Tenant" $col2_width "$tenant" 
printf "| %-*s | %-*s |\n" $col1_width "Security Group Name" $col2_width "$coresub_owner_group_name"  
printf "| %-*s | %-*s |\n" $col1_width "Securitiy Group ObjId" $col2_width "$owner_group_id"  
printf "| %-*s | %-*s |\n" $col1_width "Identity AppId" $col2_width "$appId"  
printf "| %-*s | %-*s |\n" $col1_width "AppReg ObjId" $col2_width "$appreg_objId"  
printf "| %-*s | %-*s |\n" $col1_width "SP ObjId" $col2_width "$servicePrincipalId"  
printf "| %-*s | %-*s |\n" $col1_width "Core Sub Name" $col2_width "$coreSubName"  
printf "| %-*s | %-*s |\n" $col1_width "Core Sub ID" $col2_width "$coreSub" 
printf "| %-*s | %-*s |\n" $col1_width "Region of Resources" $col2_width "$location"  
printf "| %-*s | %-*s |\n" $col1_width "Resource Group" $col2_width "$rgname" 
printf "| %-*s | %-*s |\n" $col1_width "RG Tag" $col2_width "$initTag"  
printf "| %-*s | %-*s |\n" $col1_width "Storage Account" $col2_width "$storage_account_name" 
printf "| %-*s | %-*s |\n" $col1_width "SA Delete Lock" $col2_width "$tfstate_delete_lock_name"  
printf "| %-*s | %-*s |\n" $col1_width "Container Name" $col2_width "$container_name"  
echo "-------------------------------------------------------------------"

