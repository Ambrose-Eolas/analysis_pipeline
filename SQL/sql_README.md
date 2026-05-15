# SQL — Survey Response Extraction Queries

These queries extract and reshape survey response data from a
normalised relational database into wide-format datasets ready
for Python-based analysis.

---

## The Problem: EAV Schema

Survey responses are stored in an **Entity-Attribute-Value (EAV)**
schema — a common pattern in survey platforms where flexibility
is prioritised over query convenience. Each respondent-product-visit
combination produces dozens of rows, one per attribute:

| CustomerID | ProductName | VisitDesc | Attribute                        | AnswerScore |
|------------|-------------|-----------|----------------------------------|-------------|
| 1001       | Product_A   | Visit 3   | Overall Opinion-Liking-Product   | 7           |
| 1001       | Product_A   | Visit 3   | Preparation-Experience-Easy to dissolve | 8      |
| 1001       | Product_A   | Visit 3   | Product Benefits-Agreement-Enjoyment | 6        |

Analysis requires **one row per respondent-product-visit** with
attributes as columns — a PIVOT operation across potentially
30-40 attributes.

---

## Additional Complexity

**Non-unique CustomerIDs**
CustomerIDs repeat across products within the same study. A
three-column composite key `(CustomerID + ProductName + VisitDesc)`
is used throughout to correctly identify each unique
respondent-product-visit combination.

**Two column types requiring separate pivots**
Numeric scores (`AnswerScore`) and text blind codes (`Answer`)
cannot be pivoted in the same block. Each requires its own CTE,
then the two blocks are reunited via a `FULL OUTER JOIN` on the
composite key.

**Synonym attributes**
The same logical question appears under different attribute strings
across product studies (e.g. *"Baby will accept"*, *"Baby would accept"*,
*"Child would accept"* are the same question asked of different age
groups). Collapsing synonyms at the SQL layer — before pivoting —
produces consistent column names without requiring downstream fixes.

---

## Query Structure

### `query_day1.sql` — Simple two-block pivot

```
ScorePivot  ─┐
              ├─ FULL OUTER JOIN on composite key ─► Wide output
DigitCode   ─┘
```

Used for visits where attribute names are consistent across all
products. Straightforward two-CTE pattern.

### `query_day3.sql` — Five-CTE pipeline with synonym normalisation

```
Base → Mapped → Collapsed → ScorePivot ─┐
                                         ├─ FULL OUTER JOIN ─► Wide output
                             DigitCode  ─┘
```

Used for visits where the same question appears under different
attribute strings across studies. The `Mapped` CTE normalises
synonyms; `Collapsed` aggregates to one row per composite key
before pivoting.

---

## Key Design Decisions

**`MAX()` in `Collapsed` CTE**
Assumes at most one source row exists per composite key per
unified attribute after synonym mapping. Swap to `AVG()` if
both synonym variants can legitimately coexist and averaging
is preferred over taking the higher value.

**`FULL OUTER JOIN` for final merge**
Preserves all respondent-product-visit combinations even where
one pivot block has no rows — guards against silent data loss
when either scores or blind codes are partially missing.

**Synonym mapping in SQL, not Python**
Normalising attribute names at source means the Python pipeline
receives clean, consistent column names regardless of which
study the data came from. This removes a class of fragile
string-matching logic from the analysis layer.

---

## Usage

These queries run against a SQL Server view
(`dbo.SurveyResponsesIntegrationvw`) that integrates responses
from multiple survey waves. Product names in the `IN()` lists
have been anonymised for this repository — substitute with
actual product names from your study configuration.

Output feeds directly into the survey analysis pipeline
(`notebooks/survey_analysis_pipeline.ipynb`).
