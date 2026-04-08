# Producer Compensation POC — Implementation Guide

**Use Case:** Producer Compensation data ingestion from Azure SQL DB into Microsoft Fabric Lakehouse  
**Architecture:** File-first — blobs go to Files/, lean Delta table stores regular columns + file path pointers  
**Date:** April 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Phase 1: Azure SQL Database Setup](#4-phase-1-azure-sql-database-setup)
5. [Phase 2: Fabric Workspace Setup](#5-phase-2-fabric-workspace-setup)
6. [Demo 1: Notebook Approach](#6-demo-1-notebook-approach)
7. [Demo 2: Pipeline Approach (100% Pipeline, Zero Notebook)](#7-demo-2-pipeline-approach)
8. [Simulating Changes (Re-Ingest Demo)](#8-simulating-changes)
9. [Validation & Verification](#9-validation--verification)
10. [File Inventory](#10-file-inventory)

---

## 1. Overview

This POC demonstrates ingesting a SQL table with **6 columns** (including a JSON blob and a VARBINARY binary column) into a Fabric Lakehouse using a **file-first architecture**:

| Column | Type | Destination |
|--------|------|-------------|
| PaymentID | INT (PK) | Delta table |
| ProducerID | INT | Delta table |
| CarrierName | VARCHAR(100) | Delta table |
| PaymentDate | DATE | Delta table |
| GrossAmount | DECIMAL(12,2) | Delta table |
| PaymentDetails | NVARCHAR(MAX) — JSON | `Files/payment_details/{PaymentID}.json` |
| Attachment | VARBINARY(MAX) | `Files/attachments/{PaymentID}_attachment.bin` |

The Silver Delta table stores only regular columns + two **pointer columns** (`PaymentDetailsFilePath`, `AttachmentFilePath`) that reference the blob files.

**Two independent demos:**
- **Demo 1 — Notebook:** PySpark reads SQL → writes blobs to Files → creates Delta with MERGE/upsert
- **Demo 2 — Pipeline:** 3 activities, zero notebook dependency, pointer columns computed in SQL

---

## 2. Architecture

```
Azure SQL DB                          Fabric Lakehouse
┌─────────────────────┐               ┌──────────────────────────────────────┐
│ dbo.ProducerPayments│               │ Files/                               │
│  - PaymentID        │               │   payment_details/                   │
│  - ProducerID       │──── Blobs ───▶│     1.json, 2.json, 3.json ...      │
│  - CarrierName      │               │   attachments/                       │
│  - PaymentDate      │               │     1_attachment.bin, 2_attach...    │
│  - GrossAmount      │               │                                      │
│  - PaymentDetails   │               │ Tables/                              │
│  - Attachment       │── Regular ───▶│   producer_payments_silver (Delta)   │
└─────────────────────┘   cols +      │     PaymentID, ProducerID, ...       │
                          pointers    │     PaymentDetailsFilePath (pointer) │
                                      │     AttachmentFilePath (pointer)     │
                                      └──────────────────────────────────────┘
```

---

## 3. Prerequisites

### Azure SQL Database
- An Azure SQL Database instance (any tier)
- Network: Fabric must be able to reach the SQL DB (allow Azure services, or configure private endpoint)

### Microsoft Fabric
- A Fabric workspace with at least **Contributor** access
- A **Lakehouse** created in that workspace
- Fabric capacity (F2+ or trial)

### Authentication — Entra ID (Passwordless)
No SQL username/password or Key Vault secrets needed. The Fabric workspace managed identity (or your signed-in user) authenticates directly.

**Grant access on Azure SQL DB:**
```sql
-- Run this on your Azure SQL Database (master or target DB)
CREATE USER [<your-fabric-workspace-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<your-fabric-workspace-name>];
```

Replace `<your-fabric-workspace-name>` with your actual Fabric workspace name. This grants read-only access for ingestion.

---

## 4. Phase 1: Azure SQL Database Setup

### Step 1: Create Table and Seed Data

Run **`sql/01_create_table_and_seed.sql`** against your Azure SQL Database.

**What it does:**
- Creates `dbo.ProducerPayments` table with 7 columns (including `PaymentDetails` JSON blob and `Attachment` VARBINARY)
- Inserts 5 sample rows:
  - 4 rows have both PaymentDetails JSON and Attachment binary
  - 1 row (PaymentID 3) has NULL attachment

**How to run:**
1. Open Azure Portal → your SQL Database → **Query Editor**
2. Or use SSMS / Azure Data Studio connected to your Azure SQL DB
3. Paste the contents of `sql/01_create_table_and_seed.sql` and execute
4. Verify: `SELECT * FROM dbo.ProducerPayments` should return 5 rows

### Step 2: (Later) Simulate Changes

After running the initial demo, run **`sql/02_simulate_changes.sql`** to simulate ongoing source system changes:
- 2 new inserts (PaymentIDs 6 and 7)
- 3 updates:
  - PaymentID 2: GrossAmount reduction + chargeback in JSON + revised attachment
  - PaymentID 1: Tier upgrade in JSON blob only
  - PaymentID 3: Attachment added (was NULL)

---

## 5. Phase 2: Fabric Workspace Setup

### Step 1: Create a Lakehouse

1. Open **Microsoft Fabric** portal (`app.fabric.microsoft.com`)
2. Navigate to your workspace
3. Click **+ New** → **Lakehouse**
4. Name it: `ProducerCompLakehouse` (or any name)
5. Click **Create**

### Step 2: Create a Connection to Azure SQL DB

1. In Fabric, go to **Settings gear** → **Manage connections and gateways**
2. Click **+ New connection**
3. Select **Azure SQL Database**
4. Fill in:
   - **Server:** `<your-server>.database.windows.net`
   - **Database:** `<your-database>`
   - **Authentication:** **OAuth 2.0** (Entra ID)
5. Click **Create**
6. Note the connection name for pipeline use

### Step 3: Upload Notebook (for Demo 1)

1. In your workspace, click **+ New** → **Import Notebook**
2. Upload `notebooks/ProducerComp_Fabric_POC.ipynb`
3. Open the notebook → click the **Lakehouse** icon on the left panel
4. Attach your `ProducerCompLakehouse`

---

## 6. Demo 1: Notebook Approach

### Implementation Steps

1. **Open** `ProducerComp_Fabric_POC.ipynb` in Fabric
2. **Update config cell** (Cell 3) with your actual values:
   ```python
   server   = "<YOUR_SERVER>.database.windows.net"
   database = "<YOUR_DB>"
   ```
3. **Run cells sequentially (Cells 1–11):**

| Cell | What it does |
|------|-------------|
| Cell 3 | Gets Entra ID token, sets up JDBC URL and file paths |
| Cell 5 | Reads `dbo.ProducerPayments` via JDBC → Spark DataFrame |
| Cell 7 | Creates directories (`payment_details/`, `attachments/`) |
| Cell 8 | Writes each `PaymentDetails` as `{PaymentID}.json` |
| Cell 9 | Writes each `Attachment` as `{PaymentID}_{filename}.bin` (skips NULLs) |
| Cell 10 | Builds Silver Delta table with MERGE — regular cols + file path pointers |
| Cell 11 | Reads Delta, follows pointers, displays actual file content (proof) |

### What to show in demo
- **Files section** of the Lakehouse: browse `payment_details/` and `attachments/` folders
- **Tables section**: `producer_payments_silver` Delta table — lean, no blobs, just pointers
- **Cell 11 output**: proves pointers resolve to actual file content
- **No `.crc` files**: Python native I/O avoids Hadoop checksum artifacts

### Re-Ingest Demo
1. Run `sql/02_simulate_changes.sql` on Azure SQL DB
2. Re-run Cells 5–11 in the notebook
3. Show: new files created, existing files overwritten, Delta MERGE handles upserts

---

## 7. Demo 2: Pipeline Approach (100% Pipeline, Zero Notebook)

This pipeline has **3 activities and zero notebook dependency**. The key insight: pointer columns are computed in the SQL query via `CONCAT()` + `CASE WHEN`, so the Copy Activity writes them directly.

### Pipeline Architecture

```
┌──────────────────┐
│ Lookup_BlobData  │  ← Fetches PaymentDetails + Attachment per row
│ (SQL → result)   │
└────────┬─────────┘
         │
┌────────▼──────────────────┐
│ ForEach_WriteBlobs        │  ← Parallel (batch=5)
│  ├─ Write .json file      │     Files/payment_details/{PaymentID}.json
│  └─ If attachment exists: │
│       Write .bin file     │     Files/attachments/{PaymentID}_attachment.bin
└────────┬──────────────────┘
         │
┌────────▼──────────────────────┐
│ Copy_SilverTable_WithPointers │  ← SQL computes pointer columns inline
│ SQL → Silver Delta (Overwrite)│
└───────────────────────────────┘
```

### Step-by-Step Implementation in Fabric UI

#### Step 1: Create the Pipeline

1. In your Fabric workspace, click **+ New** → **Data pipeline**
2. Name it: `PL_ProducerComp_Ingest`
3. Click **Create** — this opens the pipeline canvas

#### Step 2: Activity 1 — Lookup_BlobData

1. From the **Activities** toolbar, drag **Lookup** onto the canvas
2. Rename it to `Lookup_BlobData`
3. **Settings tab:**
   - **Connection:** Select your Azure SQL DB connection
   - **Use query:** Select **Query**
   - **Query:**
     ```sql
     SELECT PaymentID, PaymentDetails,
            CAST(Attachment AS NVARCHAR(MAX)) AS AttachmentStr
     FROM dbo.ProducerPayments
     ```
   - **First row only:** ❌ **Unchecked** (we need all rows)

#### Step 3: Activity 2 — ForEach_WriteBlobs

1. Drag **ForEach** onto the canvas
2. Rename it to `ForEach_WriteBlobs`
3. **Draw a dependency arrow** from `Lookup_BlobData` → `ForEach_WriteBlobs` (on success)
4. **Settings tab:**
   - **Sequential:** ❌ **Unchecked** (parallel processing)
   - **Batch count:** `5`
   - **Items:** Click the expression box → use dynamic content:
     ```
     @activity('Lookup_BlobData').output.value
     ```

5. **Double-click** the ForEach to open its inner canvas

##### Inner Activity 2a: Write_PaymentDetails_JSON

1. Inside the ForEach, drag a **Copy Data** activity
2. Rename it to `Write_PaymentDetails_JSON`
3. **Source tab:**
   - **Connection:** Azure SQL DB
   - **Use query:** Select **Query**
   - **Query (dynamic content):**
     ```
     @concat('SELECT PaymentDetails AS [Content] FROM dbo.ProducerPayments WHERE PaymentID = ', item().PaymentID)
     ```
4. **Destination tab:**
   - **Connection:** Your Lakehouse
   - **Root folder:** **Files**
   - **File path:**
     - Folder: `payment_details`
     - File name (dynamic): `@concat(item().PaymentID, '.json')`
   - **File format:** Text/JSON

##### Inner Activity 2b: If_HasAttachment

1. Inside the ForEach, drag an **If Condition** activity
2. Rename it to `If_HasAttachment`
3. **Draw a dependency arrow** from `Write_PaymentDetails_JSON` → `If_HasAttachment` (on success)
4. **Expression:**
   ```
   @not(empty(item().AttachmentStr))
   ```

5. Click the **✓ True** (checkmark) tab to open the "If True" canvas

##### Inner Activity 2c: Write_Attachment_File (inside If True)

1. Inside the **True** branch, drag a **Copy Data** activity
2. Rename it to `Write_Attachment_File`
3. **Source tab:**
   - **Connection:** Azure SQL DB
   - **Use query:** Select **Query**
   - **Query (dynamic content):**
     ```
     @concat('SELECT CAST(Attachment AS NVARCHAR(MAX)) AS [Content] FROM dbo.ProducerPayments WHERE PaymentID = ', item().PaymentID)
     ```
4. **Destination tab:**
   - **Connection:** Your Lakehouse
   - **Root folder:** **Files**
   - **File path:**
     - Folder: `attachments`
     - File name (dynamic): `@concat(item().PaymentID, '_attachment.bin')`
   - **File format:** Binary/Text

6. Navigate back to the main pipeline canvas (breadcrumb at top)

#### Step 4: Activity 3 — Copy_SilverTable_WithPointers

1. Drag **Copy Data** onto the main canvas
2. Rename it to `Copy_SilverTable_WithPointers`
3. **Draw a dependency arrow** from `ForEach_WriteBlobs` → `Copy_SilverTable_WithPointers` (on success)
4. **Source tab:**
   - **Connection:** Azure SQL DB
   - **Use query:** Select **Query**
   - **Query:**
     ```sql
     SELECT PaymentID, ProducerID, CarrierName, PaymentDate, GrossAmount,
            CONCAT('Files/payment_details/', CAST(PaymentID AS VARCHAR(20)), '.json')
                AS PaymentDetailsFilePath,
            CASE WHEN Attachment IS NOT NULL
                 THEN CONCAT('Files/attachments/', CAST(PaymentID AS VARCHAR(20)), '_attachment.bin')
                 ELSE NULL
            END AS AttachmentFilePath
     FROM dbo.ProducerPayments
     ```
5. **Destination tab:**
   - **Connection:** Your Lakehouse
   - **Root folder:** **Tables**
   - **Table name:** `producer_payments_silver`
   - **Table action:** **Overwrite**

#### Step 5: Validate and Run

1. Click **Validate** in the toolbar — ensure no errors
2. Click **Run** to execute the pipeline
3. Monitor progress in the output panel — each activity shows start/end time and row counts

#### Step 6: Verify Results

1. Open your Lakehouse
2. **Files section:** Check `payment_details/` and `attachments/` folders for individual files
3. **Tables section:** Open `producer_payments_silver` — should show regular columns + pointer columns, no blob data

### Pipeline JSON Reference

The full pipeline JSON definition is in **`pipeline/PL_ProducerComp_Ingest.json`**. You can use it as a reference or import it directly if Fabric supports JSON import for pipelines.

---

## 8. Simulating Changes

To demonstrate the pipeline/notebook handling ongoing changes:

1. **Run** `sql/02_simulate_changes.sql` on Azure SQL DB
2. **Re-run** the notebook (Demo 1) or re-trigger the pipeline (Demo 2)
3. **Observe:**
   - New files appear: `6.json`, `7.json`, `6_attachment.bin`
   - Updated files overwritten: `1.json`, `2.json`, `2_attachment.bin`, `3_attachment.bin`
   - Delta table: 7 rows (Notebook MERGE upserts; Pipeline overwrites all)

### Changes Summary

| PaymentID | Change |
|-----------|--------|
| 1 | JSON updated — tier upgraded to Gold |
| 2 | GrossAmount, JSON, and Attachment all updated |
| 3 | Attachment added (was NULL) |
| 6 | New row — with attachment |
| 7 | New row — no attachment |

---

## 9. Validation & Verification

### What to check after each run

| Item | Where | Expected |
|------|-------|----------|
| JSON files | Lakehouse → Files → `payment_details/` | One `.json` per PaymentID |
| Attachment files | Lakehouse → Files → `attachments/` | One `.bin` per non-NULL Attachment |
| No `.crc` files | Lakehouse → Files | Only `.json` and `.bin`, no checksum files |
| Silver Delta table | Lakehouse → Tables → `producer_payments_silver` | 5 rows initial, 7 after changes |
| Pointer columns | Silver Delta table | `PaymentDetailsFilePath` populated for all; `AttachmentFilePath` NULL where no attachment |
| File content | Open any `.json` from Files section | Valid, pretty-printed JSON |

### Verification Queries (in Fabric notebook or SQL endpoint)

```sql
-- Row count
SELECT COUNT(*) FROM producer_payments_silver;

-- Check pointer columns
SELECT PaymentID, PaymentDetailsFilePath, AttachmentFilePath
FROM producer_payments_silver
ORDER BY PaymentID;

-- Find rows with no attachment
SELECT PaymentID, CarrierName
FROM producer_payments_silver
WHERE AttachmentFilePath IS NULL;
```

---

## 10. File Inventory

```
ProducerCompPOC/
├── docs/
│   └── Implementation_Guide.md          ← This document
├── sql/
│   ├── 01_create_table_and_seed.sql     ← Create table + 5 sample rows
│   └── 02_simulate_changes.sql          ← 2 inserts + 3 updates for re-ingest demo
├── notebooks/
│   ├── ProducerComp_Fabric_POC.ipynb    ← Demo 1: Full notebook (cells 1-17)
│   └── PL_BuildSilverDelta.ipynb        ← (Optional) Diagnostic notebook, not used by pipeline
└── pipeline/
    └── PL_ProducerComp_Ingest.json      ← Demo 2: 100% pipeline JSON definition
```

---

## Appendix: REST API Pipeline Trigger

To trigger the pipeline programmatically (e.g., from another notebook or external system):

```python
import requests

workspace_id = "<YOUR_WORKSPACE_ID>"
pipeline_id  = "<YOUR_PIPELINE_ID>"
fabric_token = mssparkutils.credentials.getToken("https://api.fabric.microsoft.com")

response = requests.post(
    f"https://api.fabric.microsoft.com/v1/workspaces/{workspace_id}/items/{pipeline_id}/jobs/instances?jobType=Pipeline",
    headers={
        "Authorization": f"Bearer {fabric_token}",
        "Content-Type": "application/json"
    }
)

print(f"Status: {response.status_code}")
# 202 = Pipeline started successfully
```

Find your `workspace_id` and `pipeline_id` in the Fabric portal URL when viewing the pipeline.
