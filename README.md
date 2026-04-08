# Fabric Mixed Data Ingestion

File-first architecture for ingesting SQL tables with mixed data (structured columns + JSON blobs + binary attachments) into Microsoft Fabric Lakehouse. Blobs go to Files/, lean Delta table stores pointers. Includes PySpark notebook and zero-code pipeline demos with Entra ID auth.

---

## Problem Statement

Enterprise source systems often store **mixed data** in a single SQL table — structured columns alongside large unstructured content:

| Data Type | Example | Characteristics |
|-----------|---------|----------------|
| **Structured** | PaymentID, Amount, Date | Small, queryable, filterable |
| **JSON blobs** | Commission details, metadata | Variable-size, semi-structured |
| **Binary attachments** | PDFs, scanned documents | Large, opaque, rarely queried |

The naive approach — copying everything into a single Delta table — creates problems:

- **Bloated Parquet files** — analytical queries on 5 small columns must scan past multi-KB/MB blob columns in the same row group
- **Wasted compute** — a simple `SELECT SUM(GrossAmount)` reads orders of magnitude more data than necessary
- **Poor predicate pushdown** — Parquet min/max statistics are useless on blob columns
- **Higher Fabric capacity cost** — CU consumption scales with data scanned, not data returned

## Solution: File-First Architecture

Separate concerns at ingestion time:

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

1. **JSON blobs** → individual `.json` files in `Files/payment_details/`
2. **Binary attachments** → individual `.bin` files in `Files/attachments/`
3. **Structured columns + pointer paths** → lean Silver Delta table in `Tables/`

The Delta table stores two **pointer columns** (`PaymentDetailsFilePath`, `AttachmentFilePath`) that reference the blob files by path. Analytical queries run fast on the lean table; blob content is retrieved on-demand by following the pointers.

## Two Implementation Approaches

This repo provides two independent, fully working demos:

### Demo 1: PySpark Notebook

- Reads SQL via JDBC → writes blobs with native Python I/O → builds Delta with **MERGE/upsert**
- Incremental — re-runs update changed files and upsert Delta rows
- No `.crc` checksum artifacts (uses Python I/O, not Hadoop)

### Demo 2: Fabric Data Pipeline (Zero Code)

- 3 pipeline activities, **zero notebook dependency**
- Pointer columns computed inline in SQL (`CONCAT()` + `CASE WHEN`), written directly by Copy Activity
- ForEach with parallel batching writes blob files
- Full refresh via table overwrite

| | Notebook | Pipeline |
|---|---|---|
| Blob writing | Python native I/O | ForEach + Copy Activity |
| Delta strategy | MERGE (upsert) | Overwrite (full refresh) |
| Change handling | Incremental | Full reload |
| Code required | PySpark | None (SQL expressions only) |

## Key Features

- **Passwordless auth** — Microsoft Entra ID (managed identity) to Azure SQL DB, no secrets or Key Vault
- **Change simulation** — SQL scripts to insert/update rows, then re-ingest to demonstrate handling of new records, updated blobs, and previously-NULL attachments
- **End-to-end verification** — notebook cell reads Delta, follows pointers, and displays actual file content as proof

## Prerequisites

- **Azure SQL Database** (any tier) — network-accessible from Fabric
- **Microsoft Fabric** workspace with Contributor access + Lakehouse + capacity (F2+ or trial)
- **Entra ID access** granted on SQL DB:
  ```sql
  CREATE USER [<your-fabric-workspace-name>] FROM EXTERNAL PROVIDER;
  ALTER ROLE db_datareader ADD MEMBER [<your-fabric-workspace-name>];
  ```

## Quick Start

1. **Set up source data** — run [`sql/01_create_table_and_seed.sql`](sql/01_create_table_and_seed.sql) on your Azure SQL DB (creates table + 5 sample rows)
2. **Create a Fabric Lakehouse** and connection to your Azure SQL DB
3. **Choose your demo:**
   - **Notebook:** Import [`notebooks/ProducerComp_Fabric_POC.ipynb`](notebooks/ProducerComp_Fabric_POC.ipynb), update the server/database config, run all cells
   - **Pipeline:** Build the pipeline using the step-by-step guide, or reference [`pipeline/PL_ProducerComp_Ingest.json`](pipeline/PL_ProducerComp_Ingest.json)
4. **Simulate changes** — run [`sql/02_simulate_changes.sql`](sql/02_simulate_changes.sql), then re-run notebook or pipeline to see upserts/overwrites in action

See the full [Implementation Guide](docs/Implementation_Guide.md) for detailed step-by-step instructions.

## Repo Structure

```
├── docs/
│   └── Implementation_Guide.md        # Detailed walkthrough for both demos
├── sql/
│   ├── 01_create_table_and_seed.sql   # Create table + 5 sample rows
│   └── 02_simulate_changes.sql        # 2 inserts + 3 updates for re-ingest demo
├── notebooks/
│   ├── ProducerComp_Fabric_POC.ipynb  # Demo 1: Full PySpark notebook
│   └── PL_BuildSilverDelta.ipynb      # Optional diagnostic notebook
└── pipeline/
    └── PL_ProducerComp_Ingest.json    # Demo 2: Pipeline JSON definition
```

## Sample Data

The POC uses an insurance **producer compensation** scenario. Each payment row includes:

| Column | Type | Purpose |
|--------|------|---------|
| PaymentID | INT | Primary key |
| ProducerID | INT | Agent/broker identifier |
| CarrierName | VARCHAR | Insurance carrier |
| PaymentDate | DATE | Payment date |
| GrossAmount | DECIMAL | Payment amount |
| PaymentDetails | NVARCHAR(MAX) | JSON — commission type, tier, chargebacks, product lines |
| Attachment | VARBINARY(MAX) | Binary — PDF metadata (simulated) |

## When to Use This Pattern

**Good fit:**
- Source tables with JSON/XML documents or binary attachments alongside structured columns
- Blobs are accessed on-demand by key, not scanned/filtered in bulk
- Delta table performance matters (dashboards, aggregations, joins)

**Not necessary:**
- Small JSON (< 1 KB) that you actively filter/query on — inline it and use `from_json()`
- JSON that gets fully flattened into typed columns during transformation
- Binary data you never read back from the lakehouse

## License

MIT
