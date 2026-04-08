-- ============================================================
-- Producer Compensation POC - Table Setup & Sample Data
-- Target: Azure SQL Database (source system for Fabric ingestion)
-- ============================================================

CREATE TABLE dbo.ProducerPayments (
    PaymentID       INT IDENTITY(1,1) PRIMARY KEY,
    ProducerID      INT              NOT NULL,
    CarrierName     VARCHAR(100)     NOT NULL,
    PaymentDate     DATE             NOT NULL,
    GrossAmount     DECIMAL(12,2)    NOT NULL,
    PaymentDetails  NVARCHAR(MAX)    NOT NULL,  -- JSON blob
    Attachment      VARBINARY(MAX)   NULL        -- Binary document/file data
);
GO

-- ============================================================
-- Insert 5 sample rows with JSON blob data
-- ============================================================

INSERT INTO dbo.ProducerPayments (ProducerID, CarrierName, PaymentDate, GrossAmount, PaymentDetails, Attachment)
VALUES
(1001, 'Aetna', '2026-01-15', 4500.00,
 N'{
    "commission_type": "new_business",
    "policy_count": 3,
    "chargeback_amount": 0.00,
    "bonus_flag": false,
    "tier_level": "Silver",
    "product_lines": ["Medical", "Dental"],
    "notes": "Q1 group enrollment - employer ABC Corp"
 }',
 CONVERT(VARBINARY(MAX), '{"file":"commission_schedule_aetna_2026.pdf","pages":4,"size_kb":128}')),

(1002, 'UnitedHealthcare', '2026-01-20', 8200.00,
 N'{
    "commission_type": "renewal",
    "policy_count": 12,
    "chargeback_amount": 150.00,
    "bonus_flag": true,
    "tier_level": "Gold",
    "product_lines": ["Medical", "Vision", "Life"],
    "notes": "Annual renewal batch - large group"
 }',
 CONVERT(VARBINARY(MAX), '{"file":"renewal_statement_uhc_q1.pdf","pages":12,"size_kb":340}')),

(1003, 'Cigna', '2026-02-01', 3100.00,
 N'{
    "commission_type": "new_business",
    "policy_count": 1,
    "chargeback_amount": 0.00,
    "bonus_flag": false,
    "tier_level": "Bronze",
    "product_lines": ["Dental"],
    "notes": "Small group add-on through broker referral"
 }',
 NULL),  -- No attachment for this payment

(1001, 'BlueCross', '2026-02-10', 6750.00,
 N'{
    "commission_type": "override",
    "policy_count": 8,
    "chargeback_amount": 200.00,
    "bonus_flag": true,
    "tier_level": "Gold",
    "product_lines": ["Medical", "Dental", "Disability"],
    "notes": "Override payment as managing producer"
 }',
 CONVERT(VARBINARY(MAX), '{"file":"override_agreement_bcbs.pdf","pages":2,"size_kb":64}')),

(1004, 'Humana', '2026-02-15', 2900.00,
 N'{
    "commission_type": "new_business",
    "policy_count": 2,
    "chargeback_amount": 0.00,
    "bonus_flag": false,
    "tier_level": "Silver",
    "product_lines": ["Medical", "Voluntary Life"],
    "notes": "Mid-market employer - first placement"
 }',
 CONVERT(VARBINARY(MAX), '{"file":"new_business_app_humana.pdf","pages":6,"size_kb":210}'));
GO

-- Verify
SELECT * FROM dbo.ProducerPayments;
GO
