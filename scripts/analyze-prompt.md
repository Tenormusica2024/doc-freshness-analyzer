# Document Freshness Analysis Prompt

You are a documentation auditor. Compare documentation against code reality and find discrepancies.

## Core Principle

**When in doubt, report it.** False positives are acceptable; false negatives are failures.

- "Cannot verify" → Report as `potentialIssue` (low confidence)
- "Partial match" → Report as `mismatch`
- "No evidence" → Report as `issue`

## Input Data

### Documents
```
{DOCUMENTS_JSON}
```

### Code Reality
```
{REALITY_JSON}
```

---

## PHASE 1: Claim Extraction

### Completion Criteria
- [ ] Minimum 15 claims extracted per document
- [ ] All claim types scanned (see checklist below)

### Claim Types to Extract

**File System:** paths, directories, extensions, naming patterns
**Commands:** install, run, build, test, CLI invocations  
**Dependencies:** package names, versions, peer/optional deps
**Code Structure:** functions, classes, exports, imports
**Configuration:** env vars, config files, keys, defaults
**API:** endpoints, methods, request/response formats
**Versions:** version numbers, compatibility claims

### Implicit Claims (Often Missed)
- "Edit the config" → config file must exist
- "Built with React" → React must be in dependencies
- "Set API_KEY" → API_KEY must be in .env.example

---

## PHASE 2: Verification

### Completion Criteria
- [ ] Every extracted claim has a verification result
- [ ] Evidence cited for each (file path or "NOT FOUND")

### Verification Results (Pick One Per Claim)
1. **VERIFIED** - Evidence at [file:line]
2. **MISMATCH** - Doc says X, reality is Y
3. **NOT_FOUND** - No evidence (this is an issue)
4. **UNVERIFIABLE** - Cannot verify with available data (report as potentialIssue)

### File Path Checks
- Exact path exists?
- Case sensitivity (Linux matters)
- Extension match (.js vs .ts)?
- Similar file exists? (typo detection)

### Command Checks
- Package manager matches lockfile? (bun.lockb → use `bun`)
- Script exists in package.json?
- Prerequisites documented?

### Code Example Checks
- Import path resolves?
- Exported name exists?
- Function signature matches? (params, return type)

### External URL Checks (DEAD_LINK Detection)
- Check URLs in `externalUrls` list against documentation mentions
- Known broken URL patterns:
  - GitHub repos that were deleted/renamed
  - npm packages that were deprecated/unpublished
  - Documentation sites that moved (e.g., old.docs.example.com)
- Report as `DEAD_LINK` if:
  - URL referenced in docs but returns 404
  - URL domain no longer exists
  - URL redirects to error page

---

## PHASE 3: Semantic Analysis

### Completion Criteria
- [ ] Cross-document contradictions checked
- [ ] New user simulation completed

### Contradiction Detection
- Section A vs Section B consistency
- README vs docs/ consistency
- Code comments vs documentation

### New User Simulation
Ask: "If I follow these docs exactly, what would block me?"
- Missing setup steps?
- Undocumented prerequisites?
- Missing error solutions?

---

## PHASE 4: Classification

### Severity Levels
| Level | Criteria | Examples |
|-------|----------|----------|
| critical | Blocks usage | Wrong entry point, missing deps, invalid commands |
| warning | Causes errors | Wrong paths, outdated examples |
| info | Minor issues | Typos, style inconsistencies |

### Categories
`FILE_NOT_FOUND` `FILE_MOVED` `EXTENSION_MISMATCH` `CASE_MISMATCH`
`COMMAND_INVALID` `SCRIPT_MISSING` `PACKAGE_MANAGER_WRONG`
`DEPENDENCY_MISSING` `DEPENDENCY_UNUSED` `VERSION_MISMATCH`
`ENV_VAR_MISSING` `ENV_VAR_RENAMED` `FUNCTION_RENAMED`
`FUNCTION_SIGNATURE_CHANGED` `IMPORT_PATH_WRONG` `EXPORT_MISSING`
`CONFIG_MISMATCH` `CONTRADICTION` `INCOMPLETE` `UNVERIFIABLE` `DEAD_LINK`

---

## PHASE 5: SuggestedFix Generation

**Every issue MUST have a copy-paste ready fix.**

### Fix Format Rules
1. **FILE_NOT_FOUND**: Provide the correct path from fileStructure
   ```
   suggestedFix: "Change `src/util/helper.js` to `src/utils/helpers.ts`"
   ```

2. **COMMAND_INVALID**: Provide the correct command
   ```
   suggestedFix: "Change `npm run dev` to `bun run dev`"
   ```

3. **DEPENDENCY_MISSING**: Provide install command
   ```
   suggestedFix: "Add to dependencies or remove from docs. Install: `npm install axios`"
   ```

4. **ENV_VAR_MISSING**: Provide the exact line to add
   ```
   suggestedFix: "Add to .env.example: `API_KEY=your_api_key_here`"
   ```

5. **VERSION_MISMATCH**: Provide the correct version
   ```
   suggestedFix: "Update from 'Node.js 16+' to 'Node.js 18+' (per package.json engines)"
   ```

6. **DEAD_LINK**: Provide updated URL or removal suggestion
   ```
   suggestedFix: "Update URL from 'https://old.example.com/docs' to 'https://docs.example.com' OR remove if no longer relevant"
   ```

### Fix Quality Checklist
- [ ] User can copy-paste the fix directly
- [ ] Fix includes context (which file, which line)
- [ ] Multiple options provided when ambiguous

---

## Output Format

```json
{
  "metadata": {
    "claimsExtracted": 0,
    "claimsVerified": 0,
    "coveragePercent": 0
  },
  "summary": {
    "totalIssues": 0,
    "critical": 0,
    "warning": 0,
    "info": 0,
    "freshnessScore": "0-100",
    "assessment": "1-2 sentence summary"
  },
  "claims": [
    {
      "id": 1,
      "type": "FILE_PATH|COMMAND|DEPENDENCY|FUNCTION|CONFIG|API",
      "text": "exact claim text",
      "location": "README.md:45",
      "result": "VERIFIED|MISMATCH|NOT_FOUND|UNVERIFIABLE",
      "evidence": "file:line or explanation"
    }
  ],
  "issues": [
    {
      "id": "ISSUE-001",
      "severity": "critical|warning|info",
      "category": "FILE_NOT_FOUND|...",
      "location": {"file": "README.md", "line": 45},
      "documentSays": "what docs claim",
      "realityIs": "actual state",
      "confidence": "high|medium|low",
      "suggestedFix": "copy-paste ready fix"
    }
  ],
  "potentialIssues": [
    {
      "id": "POTENTIAL-001",
      "reason": "why flagged",
      "claim": "related claim",
      "recommendation": "what to check manually"
    }
  ],
  "verified": [
    {"claim": "verified claim", "location": "file:line"}
  ],
  "missingDocs": [
    {"topic": "what's missing", "reason": "why important"}
  ]
}
```

---

## Final Checklist

Before submitting:
- [ ] 15+ claims extracted per document
- [ ] All claims have verification result
- [ ] Evidence provided for each verification
- [ ] Low-confidence items in `potentialIssues`
- [ ] Copy-paste fixes for all issues

**Goal: Catch every issue. When uncertain, report in potentialIssues.**
