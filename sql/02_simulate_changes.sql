-- ============================================================
-- Simulate ongoing INSERTS and UPDATES (run during demo)
-- This mimics the source system receiving new payments
-- and corrections to existing ones
-- ============================================================

-- =====================
-- BATCH 1: New inserts
-- =====================

INSERT INTO dbo.ProducerPayments (ProducerID, CarrierName, PaymentDate, GrossAmount, PaymentDetails, Attachment)
VALUES
(1002, 'Aetna', '2026-03-01', 5300.00,
 N'{
    "commission_type": "new_business",
    "policy_count": 4,
    "chargeback_amount": 0.00,
    "bonus_flag": false,
    "tier_level": "Gold",
    "product_lines": ["Medical", "Dental", "Vision"],
    "notes": "New large group placement - spring enrollment"
 }',
 CONVERT(VARBINARY(MAX), '{"file":"group_app_aetna_spring.pdf","pages":8,"size_kb":275}')),

(1005, 'Cigna', '2026-03-05', 1800.00,
 N'{
    "commission_type": "new_business",
    "policy_count": 1,
    "chargeback_amount": 0.00,
    "bonus_flag": false,
    "tier_level": "Bronze",
    "product_lines": ["Dental"],
    "notes": "Small group - new producer first sale"
 }',
 NULL);  -- New producer, no attachment yet
GO

-- =====================
-- BATCH 2: Update regular column + JSON blob
-- =====================

-- Scenario: Chargeback applied to PaymentID 2, reducing gross amount + updated attachment
UPDATE dbo.ProducerPayments
SET GrossAmount   = 8050.00,
    PaymentDetails = N'{
    "commission_type": "renewal",
    "policy_count": 12,
    "chargeback_amount": 300.00,
    "bonus_flag": true,
    "tier_level": "Gold",
    "product_lines": ["Medical", "Vision", "Life"],
    "notes": "Annual renewal batch - large group. UPDATED: additional chargeback applied"
 }',
    Attachment = CONVERT(VARBINARY(MAX), '{"file":"renewal_statement_uhc_q1_revised.pdf","pages":14,"size_kb":385}')
WHERE PaymentID = 2;
GO

-- Scenario: Producer 1001 got tier upgrade in the JSON blob
UPDATE dbo.ProducerPayments
SET PaymentDetails = N'{
    "commission_type": "new_business",
    "policy_count": 3,
    "chargeback_amount": 0.00,
    "bonus_flag": true,
    "tier_level": "Gold",
    "product_lines": ["Medical", "Dental"],
    "notes": "Q1 group enrollment - ABC Corp. UPDATED: tier upgraded to Gold after volume review"
 }'
WHERE PaymentID = 1;
GO

-- Scenario: Attach a document to PaymentID 3 (previously NULL)
UPDATE dbo.ProducerPayments
SET Attachment = CONVERT(VARBINARY(MAX), '{"file":"broker_referral_cigna.pdf","pages":1,"size_kb":32}')
WHERE PaymentID = 3;
GO

-- Verify all rows after changes
SELECT * FROM dbo.ProducerPayments ORDER BY PaymentID;
GO
