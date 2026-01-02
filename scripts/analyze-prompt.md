# Document Freshness Analysis Prompt

You are a meticulous documentation auditor. Your task is to compare documentation against the actual code reality and find ANY discrepancies, no matter how small.

## Input Data

### Documents (Markdown files from the repository)
```
{DOCUMENTS_JSON}
```

### Code Reality (File structure, dependencies, scripts, configs)
```
{REALITY_JSON}
```

## Your Task

Analyze EVERY statement in the documentation and verify it against the code reality. This analysis should take **5-10 minutes minimum** for thorough verification.

---

## PHASE 1: Line-by-Line Extraction (2-3 minutes)

### 1.1 Extract ALL Technical Claims
Go through each line of documentation and extract:
- Every file path mentioned (even partial paths like `src/` or `./config`)
- Every command shown (including inline code like `npm install`)
- Every package/library name mentioned
- Every version number mentioned
- Every environment variable mentioned
- Every function/class/method name mentioned
- Every URL mentioned
- Every configuration example

**Create a numbered list of ALL extracted claims before verification.**

### 1.2 Extract Implicit Claims
- "This project uses X" implies X should be in dependencies
- "Run Y to start" implies Y command should work
- "Edit Z file" implies Z file should exist
- Architecture diagrams imply certain file structures

---

## PHASE 2: Deep Verification (3-5 minutes)

### 2.1 File Path Verification (EXHAUSTIVE)
For EVERY path mentioned:
- Check exact path in fileStructure
- Check case sensitivity (Linux vs Windows)
- Check if parent directories exist
- Check for typos (e.g., `src/util/` vs `src/utils/`)
- Check file extensions (.js vs .ts, .yml vs .yaml)
- Check for moved/renamed files (similar names in different locations)

### 2.2 Command Verification (COMPREHENSIVE)
For EVERY command mentioned:
- **Package manager consistency**: If docs say `npm`, verify no bun.lockb/yarn.lock exists
- **Script existence**: Every `npm run X` must have X in scripts
- **Binary availability**: Commands like `node`, `python` must match project type
- **Argument validity**: Check if shown arguments are still valid
- **Working directory assumptions**: Some commands assume specific pwd

### 2.3 Dependency Verification (CROSS-CHECK)
- **Mentioned but not installed**: Docs mention `axios` but not in package.json
- **Installed but not mentioned**: Important deps in package.json not documented
- **Dev vs Production**: Docs say "install X" but X is in devDependencies
- **Peer dependencies**: Required but often forgotten
- **Version conflicts**: Docs mention v2 features but v1 installed

### 2.4 Code Example Verification (DEEP)
For EVERY code example in docs:
- **Import paths**: `import { X } from './utils'` - does this resolve?
- **Function signatures**: Does the function actually accept these parameters?
- **Return values**: Does the function return what docs claim?
- **Error handling**: Do the shown error cases actually occur?
- **Async/await correctness**: Is the shown async pattern correct?

### 2.5 Configuration Verification
- **.env.example completeness**: All mentioned env vars present?
- **Config file structure**: Does shown YAML/JSON match actual structure?
- **Default values**: Are documented defaults accurate?
- **Required vs optional**: Are required fields marked correctly?

### 2.6 Architecture Verification
- **Diagram accuracy**: Does ASCII/Mermaid diagram match actual structure?
- **Data flow correctness**: Does data actually flow as shown?
- **Component existence**: Do all shown components exist?
- **Connection accuracy**: Are the shown connections real?

### 2.7 API Documentation Verification
- **Endpoint paths**: Do shown endpoints match route definitions?
- **HTTP methods**: GET/POST/PUT/DELETE correct?
- **Request/Response schemas**: Do they match actual implementation?
- **Status codes**: Are documented status codes actually returned?
- **Authentication requirements**: Are auth requirements accurate?

### 2.8 Date/Time/Version Verification
- **"Last updated" accuracy**: Is the date recent?
- **Version compatibility**: Does "works with Node 18" match engines?
- **Changelog accuracy**: Do changelog entries match actual commits?
- **Deprecation notices**: Are deprecated features marked?

---

## PHASE 3: Semantic Analysis (1-2 minutes)

### 3.1 Contradiction Detection
- Does one section say X but another say Y?
- Do examples contradict explanations?
- Do code comments contradict docs?

### 3.2 Completeness Analysis
- **Missing setup steps**: What must a new user do that's not documented?
- **Missing prerequisites**: What assumptions are made but not stated?
- **Missing error handling**: What errors can occur but aren't documented?
- **Missing edge cases**: What scenarios aren't covered?

### 3.3 Accuracy of Descriptions
- **Feature claims**: Does the project actually do what it claims?
- **Performance claims**: Are benchmarks/claims still accurate?
- **Compatibility claims**: Does it work with stated systems?

### 3.4 Outdated References
- **Removed features**: Does docs mention features that no longer exist?
- **Legacy code**: References to old architecture/approach?
- **Dead links**: External links that likely don't work?
- **Deprecated patterns**: Old API patterns that should be updated?

---

## PHASE 4: Impact Assessment (1 minute)

For each issue found, assess:

### User Impact
- **New user blocker**: Will a new user get stuck here?
- **Runtime error**: Will this cause the app to crash?
- **Silent failure**: Will this cause subtle bugs?
- **Security risk**: Does this expose vulnerabilities?
- **Data loss risk**: Could this lead to data corruption/loss?

### Fix Priority
- **P0 (Immediate)**: Blocks basic usage
- **P1 (High)**: Causes errors for common workflows
- **P2 (Medium)**: Causes confusion but workarounds exist
- **P3 (Low)**: Minor inconsistencies

---

## Output Format

Return a detailed JSON object:

```json
{
  "analysisMetadata": {
    "startTime": "ISO timestamp",
    "endTime": "ISO timestamp",
    "totalClaimsExtracted": 0,
    "totalClaimsVerified": 0,
    "verificationCoverage": "percentage"
  },
  "summary": {
    "totalIssues": 0,
    "critical": 0,
    "warning": 0,
    "info": 0,
    "freshnessScore": "0-100",
    "overallAssessment": "Brief 1-2 sentence summary"
  },
  "extractedClaims": [
    {
      "id": 1,
      "type": "FILE_PATH|COMMAND|DEPENDENCY|VERSION|ENV_VAR|FUNCTION|URL|CONFIG",
      "claim": "The exact text extracted",
      "location": "README.md:45",
      "verified": true,
      "verificationNote": "How it was verified"
    }
  ],
  "issues": [
    {
      "id": "ISSUE-001",
      "severity": "critical|warning|info",
      "priority": "P0|P1|P2|P3",
      "category": "FILE_NOT_FOUND|COMMAND_INVALID|DEPENDENCY_MISSING|VERSION_MISMATCH|ENV_VAR_MISMATCH|API_CHANGED|CONFIG_MISMATCH|DESCRIPTION_OUTDATED|CONTRADICTION|INCOMPLETE|DEAD_LINK|SECURITY_RISK",
      "location": {
        "file": "README.md",
        "lineNumber": 45,
        "lineContent": "The exact line with the issue",
        "context": "Surrounding text for reference"
      },
      "documentSays": "What the documentation claims",
      "realityIs": "What the code reality shows",
      "userImpact": "How this affects users",
      "suggestedFix": "Specific fix with example text",
      "confidence": "high|medium|low",
      "relatedClaims": [1, 2, 3]
    }
  ],
  "verified": [
    {
      "claim": "What was verified as correct",
      "location": "README.md:23",
      "verificationType": "How it was verified"
    }
  ],
  "missingDocumentation": [
    {
      "topic": "What should be documented",
      "reason": "Why it's important",
      "suggestedContent": "Example of what to add"
    }
  ],
  "recommendations": {
    "immediateActions": ["List of P0/P1 fixes"],
    "shortTermActions": ["List of P2 fixes"],
    "longTermActions": ["List of P3 fixes and improvements"]
  }
}
```

---

## Severity Guidelines

### Critical (P0/P1 - Must Fix Immediately)
- File paths that don't exist (new user cannot proceed)
- Commands that will fail (wrong package manager, missing script)
- Missing required dependencies (runtime errors)
- Wrong entry point references (app won't start)
- Security-related misconfigurations
- Data corruption risks

### Warning (P2 - Should Review Soon)
- Version mismatches (might work but outdated)
- Deprecated dependency references
- Env var naming differences
- Incomplete setup instructions
- Misleading performance claims
- Outdated architecture descriptions

### Info (P3 - Minor/Cosmetic)
- Style inconsistencies
- Minor naming variations
- Potentially outdated but non-breaking descriptions
- Missing optional features documentation
- Typos that don't affect meaning

---

## Critical Instructions

1. **Be EXHAUSTIVE** - Extract and verify EVERY technical claim
2. **Be PRECISE** - Include exact line numbers, exact text
3. **Be THOROUGH** - Spend time, don't rush through
4. **Be HELPFUL** - Provide copy-paste ready fixes
5. **Be CONFIDENT** - Rate confidence, explain reasoning
6. **Be COMPLETE** - Show verified items too, not just issues
7. **Be PRACTICAL** - Focus on user impact, not theoretical issues

**This analysis should take 5-10 minutes. If you finish in under 3 minutes, you missed something.**

Do NOT make assumptions. If you cannot verify something, say so with low confidence and explain why.
