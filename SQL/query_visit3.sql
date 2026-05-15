-- ============================================================
-- Survey Response Pivot Query — Visit 3
-- ============================================================
-- Pattern: EAV (Entity-Attribute-Value) to wide format
--   with synonym normalisation before pivoting
--
-- Problem: The same logical attribute appears under different
--   string names across product studies (e.g. "Baby will accept"
--   vs "Baby would accept" vs "Child would accept" are the same
--   question). Collapsing synonyms at the SQL layer produces
--   clean, consistent column names in the output without 
--   requiring downstream fixes in Python or Excel.
--
-- Five-CTE pipeline:
--   Base      — filter rows to relevant visits and products
--   Mapped    — map synonym attribute strings to unified names
--   Collapsed — aggregate within unified attribute per composite key
--   ScorePivot— pivot unified attributes to wide format
--   DigitCode — pivot 3-digit blind code (separate Answer column)
--   Final     — FULL OUTER JOIN to reunite both pivot blocks
--
-- NOTE on MAX() vs AVG() in Collapsed CTE:
--   MAX() is used here — assumes at most one source row exists
--   per composite key per unified attribute. Switch to AVG() 
--   if both synonym variants can appear simultaneously and you
--   want an average rather than the higher value.
-- ============================================================


/* ── Step 1: Base filter ─────────────────────────────────── */
WITH Base AS (
    SELECT 
        Customerid,
        Productname,
        MissionDesc,
        Attribute,
        AnswerScore
    FROM dbo.SurveyResponsesIntegrationvw
    WHERE 
        AnswerScore IS NOT NULL
        AND MissionDesc IN ('Visit 3', 'Visit 7', 'Visit 11')
        AND Attribute <> 'Product-3DigitCode-'
        AND Productname IN (
            'Product_A',
            'Product_B',
            'Product_C',
            'Product_D',
            'Product_E',
            'Product_F',
            'Product_G',
            'Product_H',
            'Product_I',
            'Product_J',
            'Product_K',
            'Product_L',
            'Product_M',
            'Product_N',
            'Product_O',
            'Product_P',
            'Product_Q',
            'Product_R',
            'Product_S'
        )
),

/* ── Step 2: Map synonym attribute strings to unified names ─ */
-- Synonyms arise when the same question is worded differently
-- across product studies or age-group variants (infant vs child).
-- Normalising here avoids duplicate columns in the pivot output.
Mapped AS (
    SELECT
        b.Customerid,
        b.Productname,
        b.MissionDesc,
        UnifiedAttribute =
            CASE 
                -- "Would accept" synonyms
                WHEN b.Attribute IN (
                    'Product Benefits-Agreement-Baby will accept',
                    'Product Benefits-Agreement-Baby would accept',
                    'Product Benefits-Agreement-Child would accept'
                ) THEN 'Product Benefits-Agreement-Would accept'

                -- "Enjoyment" synonyms
                WHEN b.Attribute IN (
                    'Product Benefits-Agreement-Enjoyment',
                    'Product Benefits-Agreement-Enjoyed by child'
                ) THEN 'Product Benefits-Agreement-Enjoyment'

                -- "Safe for my baby/child" synonyms
                WHEN b.Attribute IN (
                    'Product Benefits-Agreement-Safe for my baby',
                    'Product Benefits-Agreement-Safe for my child'
                ) THEN 'Product Benefits-Agreement-Safe for my'

                -- "Likely to finish a bottle" synonyms
                WHEN b.Attribute IN (
                    'Product Benefits-Agreement-Child likely to finish a bottle',
                    'Product Benefits-Agreement-Baby likely to finish a bottle'
                ) THEN 'Product Benefits-Agreement-Likely to finish a bottle'

                -- All other attributes pass through unchanged
                ELSE b.Attribute
            END,
        b.AnswerScore
    FROM Base b
),

/* ── Step 3: Collapse to one row per composite key per attribute */
-- Required because synonym mapping may produce duplicate rows
-- for the same composite key after unification.
Collapsed AS (
    SELECT
        Customerid,
        Productname,
        MissionDesc,
        UnifiedAttribute AS Attribute,
        MAX(AnswerScore) AS AnswerScore   -- swap to AVG() if preferred
    FROM Mapped
    GROUP BY Customerid, Productname, MissionDesc, UnifiedAttribute
),

/* ── Step 4: Pivot unified attributes to wide format ─────── */
ScorePivot AS (
    SELECT *
    FROM (
        SELECT 
            Customerid,
            Productname,
            MissionDesc,
            Attribute,
            AnswerScore
        FROM Collapsed
    ) AS SourceTable
    PIVOT (
        MAX(AnswerScore)
        FOR [Attribute] IN (

            /* --- Core Visit-3 attributes (present in all studies) --- */
            [Product sensory and consumption-Experience-Overall taste],
            [Overall Opinion-Liking-Product],
            [Overall Opinion-Retrial-Product],
            [Preparation-Experience-Easy to dissolve in water],
            [Product sensory and consumption-Experience-Right level of sweetness],
            [Product sensory and consumption-Experience-Appearance of the powder],
            [Product sensory and consumption-Experience-Colour of the powder],
            [Product sensory and consumption-Experience-Texture of the powder],
            [Product sensory and consumption-Experience-Appearance appeal],
            [Product sensory and consumption-Experience-Aroma appeal powder],
            [Product sensory and consumption-Experience-Aroma appeal liquid],
            [Product sensory and consumption-Experience-Level of foam],
            [Product sensory and consumption-Experience-Amount of lumps],
            [Product sensory and consumption-Experience-Agreeable or pleasant to taste],
            [Product Benefits-Agreement-Good choice for daily use],
            [Product Benefits-Agreement-Acceptable odour after emptying bottle],
            [Product Benefits-Agreement-Leaves the bottle easy to clean],
            [Product Benefits-Agreement-Consume their required volume],
            [Preparation-Retrial-Preparation and mixing experience],

            /* --- Study-specific attributes (not present in all studies) --- */
            [Product Benefits-Agreement-Like Taste],
            [Product sensory and consumption-Experience-Strength of aroma powder],
            [Product sensory and consumption-Experience-Strength of prepared product],
            [Product sensory and consumption-Experience-Thickness],
            [Product Benefits-Agreement-Reassured that my baby gets the nutrition they need],
            [Product Benefits-Agreement-Excellent preparation experience],
            [Product Benefits-Agreement-Fits into daily routine],
            [Product sensory and consumption-Experience-Colour of prepared product],
            [Product Benefits-Agreement-Easy to transfer from regular formula],

            /* --- Unified synonym columns (produced by Mapped CTE above) --- */
            [Product Benefits-Agreement-Would accept],
            [Product Benefits-Agreement-Enjoyment],
            [Product Benefits-Agreement-Safe for my],
            [Product Benefits-Agreement-Likely to finish a bottle]

        )
    ) AS P
),

/* ── Step 5: Pivot 3-digit blind code (text Answer, not numeric) */
DigitCode AS (
    SELECT Customerid, Productname, MissionDesc, [Product-3DigitCode-]
    FROM (
        SELECT 
            Customerid,
            Productname,
            MissionDesc,
            [Attribute],
            Answer
        FROM dbo.SurveyResponsesIntegrationvw
        WHERE 
            [Attribute] = 'Product-3DigitCode-'
            AND MissionDesc IN ('Visit 3', 'Visit 7', 'Visit 11')
            AND Productname IN (
                'Product_A',
                'Product_B',
                'Product_C',
                'Product_D',
                'Product_E',
                'Product_F',
                'Product_G',
                'Product_H',
                'Product_I',
                'Product_J',
                'Product_K',
                'Product_L',
                'Product_M',
                'Product_N',
                'Product_O',
                'Product_P',
                'Product_Q',
                'Product_R',
                'Product_S'
            )
    ) AS SourceTable
    PIVOT (
        MAX(Answer)
        FOR [Attribute] IN ([Product-3DigitCode-])
    ) AS DigitCodePivot
)

/* ── Step 6: Final join ──────────────────────────────────── */
-- FULL OUTER JOIN on composite key to preserve all respondent-
-- product-visit combinations even where one block has no rows.
SELECT 
    COALESCE(s.Customerid,  d.Customerid)  AS Customerid,
    COALESCE(s.Productname, d.Productname) AS Productname,
    COALESCE(s.MissionDesc, d.MissionDesc) AS MissionDesc,

    /* Core attributes */
    s.[Product sensory and consumption-Experience-Overall taste],
    s.[Overall Opinion-Liking-Product],
    s.[Overall Opinion-Retrial-Product],
    s.[Preparation-Experience-Easy to dissolve in water],
    s.[Product sensory and consumption-Experience-Right level of sweetness],
    s.[Product sensory and consumption-Experience-Appearance of the powder],
    s.[Product sensory and consumption-Experience-Colour of the powder],
    s.[Product sensory and consumption-Experience-Texture of the powder],
    s.[Product sensory and consumption-Experience-Appearance appeal],
    s.[Product sensory and consumption-Experience-Aroma appeal powder],
    s.[Product sensory and consumption-Experience-Aroma appeal liquid],
    s.[Product sensory and consumption-Experience-Level of foam],
    s.[Product sensory and consumption-Experience-Amount of lumps],
    s.[Product sensory and consumption-Experience-Agreeable or pleasant to taste],
    s.[Product Benefits-Agreement-Good choice for daily use],
    s.[Product Benefits-Agreement-Acceptable odour after emptying bottle],
    s.[Product Benefits-Agreement-Leaves the bottle easy to clean],
    s.[Product Benefits-Agreement-Consume their required volume],
    s.[Preparation-Retrial-Preparation and mixing experience],

    /* Study-specific attributes */
    s.[Product Benefits-Agreement-Like Taste],
    s.[Product sensory and consumption-Experience-Strength of aroma powder],
    s.[Product sensory and consumption-Experience-Strength of prepared product],
    s.[Product sensory and consumption-Experience-Thickness],
    s.[Product Benefits-Agreement-Reassured that my baby gets the nutrition they need],
    s.[Product Benefits-Agreement-Excellent preparation experience],
    s.[Product Benefits-Agreement-Fits into daily routine],
    s.[Product sensory and consumption-Experience-Colour of prepared product],
    s.[Product Benefits-Agreement-Easy to transfer from regular formula],

    /* Unified synonym outputs */
    s.[Product Benefits-Agreement-Would accept],
    s.[Product Benefits-Agreement-Enjoyment],
    s.[Product Benefits-Agreement-Safe for my],
    s.[Product Benefits-Agreement-Likely to finish a bottle],

    d.[Product-3DigitCode-]

FROM ScorePivot s
FULL OUTER JOIN DigitCode d
  ON  s.Customerid  = d.Customerid
 AND  s.Productname = d.Productname
 AND  s.MissionDesc = d.MissionDesc;
