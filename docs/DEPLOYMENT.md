# Deployment Guide

How to deploy the project to your own Azure subscription (about 1 hour).

**You need:** an Azure account, an Outlook.com account (to send reminders), Python 3.11, and these tools:
```bash
brew install azure-cli sqlcmd
brew tap azure/functions && brew install azure-functions-core-tools@4
az login
```

## 1. Resource group and names

Pick your own names (SQL server, storage, Function App and APIM names must be unique in Azure):
```bash
RG=rg-feemgmt; LOC=centralindia
SQL_SERVER=<sql-server-name>; SQL_DB=feedb; SQL_ADMIN=sqladmin; SQL_PASSWORD='<strong-password>'
STORAGE=<storageaccountname>; FUNC_APP=<function-app-name>

az group create -n $RG -l $LOC
```

## 2. Database

```bash
az sql server create -g $RG -n $SQL_SERVER -l $LOC --admin-user $SQL_ADMIN --admin-password "$SQL_PASSWORD"
az sql server firewall-rule create -g $RG -s $SQL_SERVER -n AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
MYIP=$(curl -s https://api.ipify.org)
az sql server firewall-rule create -g $RG -s $SQL_SERVER -n MyLaptop --start-ip-address $MYIP --end-ip-address $MYIP
az sql db create -g $RG -s $SQL_SERVER -n $SQL_DB -e GeneralPurpose -f Gen5 -c 2 --compute-model Serverless \
  --use-free-limit --free-limit-exhaustion-behavior AutoPause
```
Create the tables and data:
```bash
export SQLCMDPASSWORD="$SQL_PASSWORD"
S=$SQL_SERVER.database.windows.net
sqlcmd -S $S -d $SQL_DB -U $SQL_ADMIN -i database/01_schema.sql
sqlcmd -S $S -d $SQL_DB -U $SQL_ADMIN -i database/02_seed_data.sql -v EmailUser="<gmail-name>" EmailDomain="gmail.com"
sqlcmd -S $S -d $SQL_DB -U $SQL_ADMIN -i database/03_load_test_data.sql
sqlcmd -S $S -d $SQL_DB -U $SQL_ADMIN -i database/04_audit_log.sql
```
The sample students get emails like `<gmail-name>+stu1003@gmail.com`, so all reminders arrive in your own inbox.

## 3. Azure Function

```bash
az storage account create -g $RG -n $STORAGE -l $LOC --sku Standard_LRS
az functionapp create -g $RG -n $FUNC_APP --storage-account $STORAGE --flexconsumption-location $LOC \
  --runtime python --runtime-version 3.11 --disable-app-insights
az functionapp config appsettings set -g $RG -n $FUNC_APP -o none --settings \
  "SQL_CONNECTION_STRING=Driver={ODBC Driver 18 for SQL Server};Server=tcp:$S,1433;Database=$SQL_DB;Uid=$SQL_ADMIN;Pwd=$SQL_PASSWORD;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
cd functions && func azure functionapp publish $FUNC_APP && cd ..
az functionapp keys set -g $RG -n $FUNC_APP --key-type functionKeys --key-name apim -o none
az functionapp keys list -g $RG -n $FUNC_APP --query functionKeys.apim -o tsv
```
The last command prints the function key (named `apim`). Keep it for step 5.

## 4. Entra ID (Azure portal)

**API app:**
1. Microsoft Entra ID → **App registrations** → **New registration** → name `fee-management-api` → Register.
2. **App roles** → Create app role, twice (as in `entra/app-roles.json`):
   - Display name `Fee Admin`, allowed member types **Applications**, value `Fee.Admin`
   - Display name `Fee Reader`, allowed member types **Applications**, value `Fee.Reader`
3. **Expose an API** → Application ID URI → **Add** → keep `api://<application-id>` → Save.

**Client apps** (do this for both):

| App name | Role |
|---|---|
| `fee-admin-client` | Fee.Admin |
| `fee-reader-client` | Fee.Reader |

1. **New registration** with the name above.
2. **Certificates & secrets** → New client secret → copy the **Value** (it is shown only once).
3. **API permissions** → Add a permission → **My APIs** → `fee-management-api` → **Application permissions** → tick the role → Add → **Grant admin consent**.

Note the **Directory (tenant) ID**, the API app's **Application (client) ID**, and each client app's ID and secret.

## 5. API Management (Azure portal)

1. Create an **API Management** service: pricing tier **Consumption**.
2. **Named values** → add three:
   - `func-key` = the function key from step 3 (type: Secret)
   - `tenant-id` = your tenant ID
   - `api-app-id` = the `fee-management-api` application ID
3. **APIs** → Add API → **HTTP**:

   | API | Web service URL | URL suffix | Operations |
   |---|---|---|---|
   | Student Fee API | `https://<function-app-name>.azurewebsites.net/api` | `fees` | GET `/students/{studentId}/status` |
   | Admin Fee API | `https://<function-app-name>.azurewebsites.net/api/manage` | `admin-fees` | GET `/students`, PATCH `/students/{studentId}/fee` |

4. **Policies:** open each API → **All operations** → Inbound processing → **`</>`** → replace everything with the file:
   - Student Fee API → `apim/student-api-policy.xml`
   - Admin Fee API → `apim/admin-api-policy.xml`
   - Admin Fee API → the **PATCH** operation only → `apim/admin-update-fee-policy.xml`
5. **Products** → add `Student Access` (Student Fee API) and `Admin Access` (Admin Fee API), with **Requires subscription** on, then publish both.
6. **Subscriptions** → add `Student App` (scope: Student Access) and `Admin Portal` (scope: Admin Access) → **Show keys** to get the API keys.

## 6. Logic App (reminders)

Create the SQL and Outlook connections and deploy the workflow from `logic-app/overdue-reminder-workflow.json`:
```bash
SUB=$(az account show --query id -o tsv)
C="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/connections"
M="/subscriptions/$SUB/providers/Microsoft.Web/locations/$LOC/managedApis"
az rest --method put -o none --url "$C/sql?api-version=2016-06-01" --body "{\"location\":\"$LOC\",\"properties\":{\"displayName\":\"feedb\",\"api\":{\"id\":\"$M/sql\"},\"parameterValueSet\":{\"name\":\"sqlAuthentication\",\"values\":{\"server\":{\"value\":\"$S\"},\"database\":{\"value\":\"$SQL_DB\"},\"username\":{\"value\":\"$SQL_ADMIN\"},\"password\":{\"value\":\"$SQL_PASSWORD\"}}}}}"
az rest --method put -o none --url "$C/outlook?api-version=2016-06-01" --body "{\"location\":\"$LOC\",\"properties\":{\"displayName\":\"Outlook.com\",\"api\":{\"id\":\"$M/outlook\"}}}"

python3 - > /tmp/workflow.json <<EOF
import json
conns = {n: {"connectionId": "/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/connections/" + n,
             "connectionName": n, "id": "$M/" + n} for n in ["sql", "outlook"]}
print(json.dumps({"location": "$LOC", "properties": {"state": "Enabled",
      "definition": json.load(open("logic-app/overdue-reminder-workflow.json")),
      "parameters": {"\$connections": {"value": conns}}}}))
EOF
az rest --method put -o none --body @/tmp/workflow.json \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Logic/workflows/la-fee-reminders?api-version=2019-05-01"
```
Then in the portal: resource group → **outlook** (API connection) → Edit API connection → **Authorize** → sign in → Save.

## 7. Monitoring (Azure portal)

1. Create an **Application Insights** resource (`appi-feemgmt`).
2. Function App → **Application Insights** → turn on → select `appi-feemgmt`.
3. API Management → **Application Insights** → Add → select `appi-feemgmt`. Then APIs → All APIs → Settings → turn on Application Insights logging.
4. Logic App → **Diagnostic settings** → Add → WorkflowRuntime + AllMetrics → send to the Log Analytics workspace of `appi-feemgmt`.

Queries to try are in `monitoring/queries.kql` (Application Insights → Logs).

## 8. Test

```bash
APIM=https://<apim-name>.azure-api.net
curl -H "Ocp-Apim-Subscription-Key: <student-key>" $APIM/fees/students/1003/status
```
Get an admin token (use the reader app's ID and secret to test 403):
```bash
curl -X POST https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token \
  -d grant_type=client_credentials -d client_id=<admin-client-id> \
  --data-urlencode client_secret=<admin-client-secret> -d scope=api://<api-app-id>/.default
```
```bash
curl -X PATCH $APIM/admin-fees/students/100010/fee -H "Ocp-Apim-Subscription-Key: <admin-key>" \
  -H "Authorization: Bearer <access_token>" -H "Content-Type: application/json" -d '{"paidAmount": 1000}'
```

| Test | Expected |
|---|---|
| Student status with key | 200, status `Overdue` |
| Without key | 401 |
| Calling the Function URL directly | 401 |
| Admin update with admin token | 200 |
| Admin update with reader token | 403 |
| Logic App → Run trigger | overdue students receive emails |

The first request after a break can be slow (the free database wakes up). Just retry.

## Clean up

```bash
az group delete -n $RG --yes
```
Then delete the three app registrations in Entra ID.
