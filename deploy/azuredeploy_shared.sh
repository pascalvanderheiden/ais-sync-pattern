#!/bin/bash

# Arguments
# -r Resource Group Name
# -l Location Name
# -a Cosmos DB Account
# -d Cosmos DB Database (Using shared RU's, 400 RU's are the minimum)
# -c Cosmos DB Container
# -p API Management Instance (Developer tier)
# -w Log Analytics Workspace (Logic Apps Logging)
# -k Key Vault
# -x Key Vault Cosmos DB Key Label
# -y Cosmos DB Container Partition Key
# 
# Executing it with minimum parameters:
#   ./azuredeploy.sh -r aisshared-rg -l westeurope -a aisshared-acc -d aisshared-db -c customer-con -p aisshared -w aisshared-ws -k aisshared-kv -x aissharedcosmosdb -y "/message/lastName"
#
# This script assumes that you already executed "az login" to authenticate 
#
# For Azure DevOps it's best practice to create a Service Principle for the deployement
# In the Cloud Shell:
# For example: az ad sp create-for-rbac --name aissync-sp
# Copy output JSON: AppId and password

while getopts r:l:a:d:c:p:w:k:x:y: option
do
	case "${option}"
	in
		r) RESOURCEGROUP=${OPTARG};;
		l) LOCATION=${OPTARG};;
		a) COSMOSACC=${OPTARG};;
		d) COSMOSDB=${OPTARG};;
		c) COSMOSCON=${OPTARG};;
		p) APIM=${OPTARG};;
		w) LOGANALYTICS=${OPTARG};;
		k) KV=${OPTARG};;
		x) KVCOSMOSDBLABEL=${OPTARG};;
		y) COSMOSCONPARTKEY=${OPTARG};;		
	esac
done

# Functions
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}

# Setting up some default values if not provided
# if [ -z ${RESOURCEGROUP} ]; then RESOURCEGROUP="aissync-rg"; fi 

echo "Input parameters"
echo "   Resource Group: ${RESOURCEGROUP}"
echo "   Location: ${LOCATION}"
echo "   Cosmos DB Account: ${COSMOSACC}"
echo "   Cosmos DB Database: ${COSMOSDB}"
echo "   Cosmos DB Container: ${COSMOSCON}"
echo "   API Management Instance: ${APIM}"
echo "   Log Analytics Workspace: ${LOGANALYTICS}"
echo "   Key Vault: ${KV}"
echo "   Key Vault Cosmos DB Key Label: ${KVCOSMOSDBLABEL}"
echo "   Cosmos DB Container Partition Key: ${COSMOSCONPARTKEY}"; echo

#--------------------------------------------
# Registering providers & extentions
#--------------------------------------------
echo "Registering providers"
az extension add -n eventgrid
az provider register -n Microsoft.DocumentDB
az provider register -n Microsoft.ApiManagement
az provider register -n Microsoft.Logic
az provider register -n Microsoft.OperationsManagement
az provider register -n Microsoft.EventGrid
az provider register -n Microsoft.keyvault

#--------------------------------------------
# Creating Resource group
#-------------------------------------------- 
echo "Creating resource group ${RESOURCEGROUP}"
RESULT=$(az group exists -n $RESOURCEGROUP)
if [ "$RESULT" != "true" ]
then
	az group create -l $LOCATION -n $RESOURCEGROUP
else
	echo "   Resource group ${RESOURCEGROUP} already exists"
fi

#--------------------------------------------
# Creating Cosmos DB Account
#-------------------------------------------- 
echo "Creating Cosmos DB Account ${COSMOSACC}"
RESULT=$(az cosmosdb check-name-exists -n $COSMOSACC)
if [ "$RESULT" != "true" ]
then
	az cosmosdb create -n $COSMOSACC -g $RESOURCEGROUP
	# Get Secure Connection String
	COSMOSDBKEY=$(az cosmosdb keys list -n $COSMOSACC -g $RESOURCEGROUP --type keys --query primaryMasterKey -o tsv)
else
	echo "   Cosmos DB Account ${COSMOSACC} already exists, retrieve key"
	COSMOSDBKEY=$(az cosmosdb keys list -n $COSMOSACC -g $RESOURCEGROUP --type keys --query primaryMasterKey -o tsv)
fi

#--------------------------------------------
# Creating Cosmos DB Database
#-------------------------------------------- 
echo "Creating Cosmos DB Account ${COSMOSDB}"
RESULT=$(az cosmosdb sql database show -n $COSMOSDB -a $COSMOSACC -g $RESOURCEGROUP)
if [ "$RESULT" = "" ]
then
	az cosmosdb sql database create -a $COSMOSACC -g $RESOURCEGROUP -n $COSMOSDB --throughput 400
else
	echo "   Cosmos DB Database ${COSMOSDB} already exists"
fi

#--------------------------------------------
# Creating Cosmos DB Container
#-------------------------------------------- 
echo "Creating Cosmos DB Container ${COSMOSCON}"
RESULT=$(az cosmosdb sql container show -a $COSMOSACC -g $RESOURCEGROUP -n $COSMOSCON -d $COSMOSDB)
if [ "$RESULT" = "" ]
then
	az cosmosdb sql container create -a $COSMOSACC -g $RESOURCEGROUP -n $COSMOSCON -d $COSMOSDB -p "$COSMOSCONPARTKEY"
else
	echo "   Cosmos DB Container ${COSMOSCON} already exists"
fi

#--------------------------------------------
# Creating Log Analytics Workspace
#-------------------------------------------- 
echo "Creating Log Analytics Workspace ${LOGANALYTICS}"
RESULT=$(az monitor log-analytics workspace show -g $RESOURCEGROUP -n $LOGANALYTICS)
if [ "$RESULT" = "" ]
then
	az monitor log-analytics workspace create -g $RESOURCEGROUP -n $LOGANALYTICS
else
	echo "   Log Analytics Workspace ${LOGANALYTICS} already exists"
fi

#--------------------------------------------
# Creating API Management Instance
#-------------------------------------------- 
echo "Creating API Management Instance ${APIM}"
RESULT=$(az apim check-name -n $APIM)
if [ "$RESULT" != "true" ]
then
	az apim create -n $APIM -g $RESOURCEGROUP -l $LOCATION --publisher-email email@mydomain.com --publisher-name Microsoft
else
	echo "   API Management Instance ${APIM} already exists"
fi

#--------------------------------------------
# Creating Key Vault & Secret
#-------------------------------------------- 
echo "Creating Key Vault ${KV}"
RESULT=$(az keyvault show -n $KV)
if [ "$RESULT" = "" ]
then
	az keyvault create -l $LOCATION -n $KV -g $RESOURCEGROUP
else
	echo "   Key Vault ${KV} already exists"
fi
# Check if secret already exists
RESULTKEY=$(az keyvault secret show -n $KVCOSMOSDBLABEL --vault-name $KV)
if [ "$RESULTKEY" = "" ]
then
	az keyvault secret set --vault-name "$KV" --name "$KVCOSMOSDBLABEL" --value "$COSMOSDBKEY"
else
	echo "   Key Vault Secret ${KVKVCOSMOSDBLABEL} already exists"
fi