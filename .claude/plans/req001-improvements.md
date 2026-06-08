# Implementation Plan: REQ001 Framework Improvements

Based on the improvement report at `docs/improvement-report-REQ001.md`, implement the following changes following the "script over language" principle.

## Files to Create

### 1. `docs/requirements/CR-001-propose-phase-verification-planning.md`
Change request documenting all framework improvements from REQ001 analysis.

### 2. `scripts/verify-archive.sh`
New archive quality verification script with:
- Generic checks: file duplication detection, update direction detection
- Project-specific checks: read from `deliverables/{REQ-ID}/.archiveignore`

## Files to Modify

### 3. `CLAUDE.md` (minimal: +2 lines in §4)
- Change "交付判定三层校验" to "四层校验" adding verify-archive.sh
- Add: SR4 discovers code defect → return to apply phase

### 4. `templates/handoff-template.md`
Add three optional sections:
- `## 产出规格` (depth_level, quality_anchor, structure_skeleton)
- `## 用户反馈原文` (for R2+ rounds)
- `## 设计对标清单` (for DE tasks)

### 5. `skills/mh-propose.md`
After SA/TE dispatch in standard/full modes, add:
- SA additional output: `.archiveignore` + `sa/verify-strategy.md`
- TE additional output: `te/audit-dimensions.md`
- Plan-action.md template: add `## 集成点` section

### 6. `skills/mh-archive.md`
- ARC-5: write metrics directly to output/ path (not top-level)
- SR4: add verify-archive.sh pre-check + "code defect → return to apply" rule

### 7. `agents/pm.md`
- In 禁止事项: strengthen with "用户说'安排XX做'必须通过 handoff 派发，禁止自行顶替"

### 8. `scripts/verify-qa.sh`
Add three generic checks:
- QA-8: retry handoffs (R2+) must contain user feedback
- QA-9: repair_round > 0 requires corresponding code-report-r{N}.md
- QA-10: audit report should cover audit-dimensions.md items

### 9. `scripts/verify.sh`
- B-class SA check: support both single-file (design.md) and multi-file (overview.md) modes

## Execution Order

1. Create docs/requirements/CR-001 (document the change)
2. Create scripts/verify-archive.sh
3. Modify CLAUDE.md (+2 lines)
4. Modify templates/handoff-template.md
5. Modify skills/mh-propose.md
6. Modify skills/mh-archive.md
7. Modify agents/pm.md
8. Modify scripts/verify-qa.sh
9. Modify scripts/verify.sh
