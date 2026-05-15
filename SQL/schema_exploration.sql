-- ============================================================
-- Survey Database Schema Exploration Toolkit
-- ============================================================
-- Purpose:
--   Reusable discovery queries for understanding an unfamiliar
--   survey database before building extraction or pivot queries.
--
-- Typical workflow:
--   1. Confirm view structure (columns, scale types)
--   2. Count respondents and questions to validate scope
--   3. Explore question hierarchy (groups, subgroups, attributes)
--   4. Identify attribute strings for a given product and visit
--   5. Check for duplicate product names across studies
--   6. Confirm study names and product lists before querying
--
-- All queries run against:
--   dbo.SurveyResponsesIntegrationvw  — integrated response view
--   dbo.SurveyResponsesVW             — base response view
--
-- Replace placeholder values (Product_A, Visit 1, etc.)
-- with actual values from your study configuration.
-- ============================================================


-- ============================================================
-- SECTION 1: View Structure
-- ============================================================

-- 1a. List all columns in the integration view
--     Run this first when working with an unfamiliar database
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'SurveyResponsesIntegrationvw'
ORDER BY ORDINAL_POSITION;


-- 1b. Sample raw rows to understand data shape
--     Useful for checking Answer vs AnswerScore population
SELECT TOP 50
    QuestionID,
    Question,
    Attribute,
    Answer,
    AnswerScore,
    ScaleType
FROM [dbo].[SurveyResponsesVW]
WHERE Answer IS NOT NULL
  AND Year = 2025;


-- 1c. Check what scale types exist in the view
--     Helps identify which attributes are numeric vs text
SELECT DISTINCT ScaleType, COUNT(*) AS RowCount
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
GROUP BY ScaleType
ORDER BY RowCount DESC;


-- ============================================================
-- SECTION 2: Dataset Sizing
-- ============================================================

-- 2a. Count unique respondents across the full dataset
SELECT COUNT(DISTINCT ResponseID) AS UniqueRespondents
FROM [dbo].[SurveyResponsesVW];


-- 2b. Count unique questions
SELECT COUNT(DISTINCT Questionid) AS UniqueQuestions
FROM [dbo].[SurveyResponsesIntegrationvw];


-- 2c. Count respondents for a specific product and visit
--     Use to validate expected sample size before extraction
SELECT COUNT(DISTINCT Customerid) AS UniqueRespondents
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
  AND [MissionDesc] IN ('Visit 1', 'Visit 5', 'Visit 9')
  AND [Productname] IN ('Product_A');


-- ============================================================
-- SECTION 3: Question Hierarchy
-- ============================================================

-- 3a. Explore question structure by group and subgroup
--     Gives a map of the full question hierarchy in the database
SELECT
    QuestionGroup,
    QuestionSubGroup,
    COUNT(*) AS NumQuestions
FROM [dbo].[SurveyResponsesVW]
GROUP BY QuestionGroup, QuestionSubGroup
ORDER BY QuestionGroup, QuestionSubGroup;


-- 3b. Explore the full hierarchy including SubGroup2
--     Use when SubGroup alone doesn't give enough granularity
SELECT DISTINCT
    QuestionGroup,
    QuestionSubGroup,
    QuestionSubGroup2,
    Question,
    Questionid
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
  AND [MissionDesc] IN ('Visit 3', 'Visit 7', 'Visit 11')
  AND [Productname] IN ('Product_A')
ORDER BY Questionid;


-- ============================================================
-- SECTION 4: Attribute Discovery
-- ============================================================

-- 4a. Get distinct attributes and questions for a product + visit
--     This is the key step before building a PIVOT query —
--     use the Attribute values directly in the FOR [Attribute] IN list
SELECT DISTINCT
    Question,
    Attribute
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
  AND [MissionDesc] IN ('Visit 1')
  AND [Productname] IN ('Product_A')
ORDER BY Attribute;


-- 4b. Get attributes sorted by QuestionID
--     Useful when you want attributes in survey order
SELECT DISTINCT
    Attribute,
    Question,
    ScaleType,
    Answer
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
  AND [MissionDesc] IN ('Visit 1', 'Visit 2', 'Visit 3')
ORDER BY Attribute;


-- 4c. Check attribute coverage across visits
--     Reveals which attributes appear on which visit days —
--     important for identifying visit-specific vs universal attributes
SELECT
    [MissionDesc],
    [Attribute],
    COUNT(DISTINCT Customerid) AS RespondentCount
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
  AND [Productname] IN ('Product_A')
GROUP BY [MissionDesc], [Attribute]
ORDER BY [Attribute], [MissionDesc];


-- ============================================================
-- SECTION 5: Study and Product Discovery
-- ============================================================

-- 5a. List distinct study names for a given country and year
--     Use to confirm the exact Studyname string before filtering
SELECT DISTINCT [Studyname]
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
  AND Year = 2025
  AND country = 'Country_A'
ORDER BY Studyname;


-- 5b. List distinct project names for a given year
SELECT DISTINCT project_name
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE originalsurveytype IN (
    'Danone', 'Danone1', 'Danone2',
    'Competitor', 'Competitor1', 'Competitor2'
)
  AND Year = 2025
  AND AnswerScore IS NOT NULL
ORDER BY project_name;


-- 5c. List all products within a given project
--     Use to confirm exact Productname strings before building
--     the IN() list for a pivot query
SELECT DISTINCT Productname
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE originalsurveytype IN (
    'Danone', 'Danone1', 'Danone2',
    'Competitor', 'Competitor1', 'Competitor2'
)
  AND project_name = 'Project_Name_Here'
  AND Daynumber = 'Visit 1'
  AND AnswerScore IS NOT NULL
ORDER BY Productname;


-- 5d. Check survey types present for a given study
--     Useful for confirming which originalsurveytype values
--     apply to this study before filtering
SELECT DISTINCT originalsurveytype, COUNT(*) AS RowCount
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE project_name = 'Project_Name_Here'
  AND AnswerScore IS NOT NULL
GROUP BY originalsurveytype
ORDER BY RowCount DESC;


-- ============================================================
-- SECTION 6: Data Quality Checks
-- ============================================================

-- 6a. Check for synonym attribute strings across studies
--     Run this when the same logical question appears under
--     different strings across product variants or age groups.
--     Output feeds into the Mapped CTE synonym table
--     in query_visit3.sql
SELECT DISTINCT
    [Productname],
    [Attribute]
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE AnswerScore IS NOT NULL
  AND [MissionDesc] IN ('Visit 3', 'Visit 7', 'Visit 11')
  AND [Attribute] LIKE '%accept%'   -- replace with the attribute keyword to check
ORDER BY [Attribute], [Productname];


-- 6b. Identify duplicate product names across studies
--     Products can appear in multiple studies under the same name.
--     Use RTRIM() + suffix to disambiguate before joining.
SELECT DISTINCT
    RTRIM([Productname]) + '_REF' AS [Productname_Disambiguated],
    [Studyname],
    [Attribute],
    [Question]
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE [Productname] IN ('Product_A', 'Product_B')
  AND [Studyname] = 'Study_Name_Here'
  AND [MissionDesc] = 'Visit 1'
  AND AnswerScore IS NOT NULL;


-- 6c. Check Answer vs AnswerScore population for a product
--     Some attributes store responses in Answer (text),
--     others in AnswerScore (numeric). This query reveals
--     which columns need to be handled separately in a pivot.
SELECT
    [Attribute],
    COUNT(CASE WHEN AnswerScore IS NOT NULL THEN 1 END) AS HasAnswerScore,
    COUNT(CASE WHEN Answer IS NOT NULL THEN 1 END)      AS HasAnswer,
    COUNT(CASE WHEN AnswerScore IS NULL
               AND Answer IS NOT NULL THEN 1 END)       AS TextOnlyRows
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE [Productname] IN ('Product_A')
  AND [MissionDesc] IN ('Visit 1')
GROUP BY [Attribute]
ORDER BY TextOnlyRows DESC, [Attribute];


-- 6d. Spot-check a single respondent's full answer set
--     Useful for confirming that a specific respondent's data
--     looks correct after a merge or pivot operation
SELECT
    Customerid,
    Productname,
    MissionDesc,
    Attribute,
    Answer,
    AnswerScore
FROM [dbo].[SurveyResponsesIntegrationvw]
WHERE Customerid = 99999   -- replace with actual CustomerID
  AND [Productname] IN ('Product_A')
  AND AnswerScore IS NOT NULL
ORDER BY Attribute;
