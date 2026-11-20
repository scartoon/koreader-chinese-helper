# Data for the classical-dictionary research note (#49)

Copies of the small files from `build/classical/` (git-ignored), kept for the record. The
scripts expect to run from `build/classical/`, next to `texts/`, `collated.tsv` and
`condensed.jsonl`.

- `fetch_texts.py`: the test set from zh.wikisource
- `sample.py`, `sample.tsv`: the 150 sampled occurrences
- `judgments.tsv`: the needed sense and its keyword pattern for each occurrence (status `ok`,
  `name` or `excl`)
- `measure.py`, `verdicts.py`, `verdicts.tsv`: keyword hits and the hand-corrected verdicts
- `eval_condensed.py`, `ground_v2.py`: sense retention after condensing, and the check of each
  sense against the lines it cites
- `prompt_v1.txt`, `prompt_v2.txt`: the earlier condensing prompts (v3 is
  `tools/condense_classical_prompt.txt`)
