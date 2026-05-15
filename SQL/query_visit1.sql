-- ============================================================
-- Survey Response Pivot Query — Visit 1
-- ============================================================
-- Pattern: EAV (Entity-Attribute-Value) to wide format
--
-- Problem: Survey responses are stored in a normalised EAV 
--   schema where each attribute is a separate row. Reporting
--   and analysis require a wide format — one row per 
--   respondent-product-visit combination.
--
-- Additional complexity: CustomerIDs are not unique across
--   products. A composite key (CustomerID + ProductName + 
--   VisitDesc) is used throughout to ensure correct joins.
--
-- Two pivot blocks are required:
--   Block 1 — Pivot numeric AnswerScore attributes
--   Block 2 — Pivot the Product 3-digit blind code (Answer, not AnswerScore)
--   Final    — FULL OUTER JOIN on composite key to reunite both blocks
-- ============================================================


-- Step 1: Pivot numeric AnswerScore attributes per respondent-product-visit
WITH ScorePivot AS (
    SELECT *
    FROM (
        SELECT 
            Customerid,
            [Productname],
            [MissionDesc],
            [Attribute],
            AnswerScore
        FROM [SurveyResponsesIntegrationvw]
        WHERE 
            AnswerScore IS NOT NULL
            AND [MissionDesc] IN ('Visit 1', 'Visit 5', 'Visit 9')
            AND [Productname] IN (
                'Product_A'
            )
            AND [Attribute] != 'Product-3DigitCode-'
    ) AS SourceTable
    PIVOT (
        MAX(AnswerScore)
        FOR [Attribute] IN (
            [Pack functionality-Experience-Tamper evidence reassurance],
            [Pack functionality-Experience-Easy to Store],
            [Pack functionality-Experience-Safety and Hygiene]
        )
    ) AS ScorePivot
),

-- Step 2: Pivot the Product 3-digit blind code using the same composite key
-- Note: blind code is stored in the Answer column (text), not AnswerScore (numeric)
DigitCode AS (
    SELECT Customerid, Productname, MissionDesc, [Product-3DigitCode-]
    FROM (
        SELECT 
            Customerid,
            Productname,
            MissionDesc,
            [Attribute],
            Answer
        FROM [SurveyResponsesIntegrationvw]
        WHERE 
            [Attribute] = 'Product-3DigitCode-'
            AND [MissionDesc] IN ('Visit 1', 'Visit 5', 'Visit 9')
            AND [Productname] IN (
                'Product_A'
            )
    ) AS SourceTable
    PIVOT (
        MAX(Answer)
        FOR [Attribute] IN ([Product-3DigitCode-])
    ) AS DigitCodePivot
)

-- Step 3: Rejoin both pivot blocks on composite key
-- FULL OUTER JOIN used to preserve rows that may be missing
-- from either block due to partial data entry
SELECT 
    COALESCE(s.Customerid, d.Customerid)   AS Customerid,
    COALESCE(s.Productname, d.Productname) AS Productname,
    COALESCE(s.MissionDesc, d.MissionDesc) AS MissionDesc,
    s.[Pack functionality-Experience-Tamper evidence reassurance],
    s.[Pack functionality-Experience-Easy to Store],
    s.[Pack functionality-Experience-Safety and Hygiene],
    d.[Product-3DigitCode-]
FROM ScorePivot s
FULL OUTER JOIN DigitCode d
    ON  s.Customerid  = d.Customerid
    AND s.Productname = d.Productname
    AND s.MissionDesc = d.MissionDesc;
