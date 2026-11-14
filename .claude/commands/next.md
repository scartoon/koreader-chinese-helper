Work on the next task from this repo's GitHub issue queue.

Pick the task:
- First run `gh issue list --state open --label in-progress`. If an issue comes back, resume it: read the issue and all its comments, check out the branch named in the latest progress comment, and continue from there.
- Otherwise take the open issue with the highest priority (P1, then P2, then P3; unlabelled last), lowest number first. Skip issues labelled needs-simon or draft, and issues whose "Depends on #X" issue is still open.
- If nothing qualifies, say so and stop.

The issue body is your brief: treat it as the prompt for this task. Where my later comments conflict with the body, the comments win. If the body is too thin to act on without guessing, don't guess: post your questions as a comment, label the issue needs-simon, and go on to the next issue.

Start: add the in-progress label, create the branch `issue-<N>-<short-slug>` (or reuse it if resuming), and post a comment with your plan.

While working:
- Follow CLAUDE.md. For roadmap phases, also follow the roadmap's shared rules and the phase's own section.
- My usage window can end at any moment, even mid-turn. After each meaningful step (one plan step done, tests passing, a measurement taken), commit, push the branch, and post a short issue comment: what's done, what's next, any numbers measured, and the branch name. Never let more than about 20 minutes of work go unpushed.
- If you reach a stop-and-ask condition or need a decision from me, post the question as a comment, replace in-progress with needs-simon, push, and stop. Don't pick up another issue in the same session unless I ask.
- If you notice follow-up work outside this issue's scope, file it as a new issue labelled draft, with a short note, rather than doing it.

Finish: merge to main with a commit message that includes "Closes #<N>", do the release steps if the brief calls for them, update the roadmap's Status and Findings for roadmap phases, post a summary comment (what shipped, measurements, anything later issues should know), and remove in-progress. Then tell me in one or two lines what's next in the queue.
