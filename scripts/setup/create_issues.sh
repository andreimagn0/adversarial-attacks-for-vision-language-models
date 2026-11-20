#!/usr/bin/env bash
# =============================================================================
# CS 553 - Exploring Adversarial Attacks Against Vision-Language Models
# Bulk-creates labels, milestones, and issues with the GitHub CLI.
#
# Usage:
#   gh auth login                              # once
#   DRY_RUN=1 ./create_issues.sh               # preview only, creates nothing
#   ./create_issues.sh                         # run from inside the repo clone
#   GH_REPO=owner/repo ./create_issues.sh      # or target a repo explicitly
#
# Re-running is safe: labels are updated, and existing milestones and issues
# (matched by exact title) are skipped instead of duplicated.
#
# Framing: one base defense (image preprocessing) stress-tested by attacks from
# the proposal references: FGSM/BIM/PGD, the CLIP spectral attack (Paredes La
# Torre), surrogate-ensemble transfer (Hu et al.), adaptive attacks, CTP (stretch).
#
# Issues are NOT assigned to anyone. The five track labels (track-a ... track-e)
# are balanced bundles of work (8-9 issues each) that people can claim.
# =============================================================================
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
FAKE_NUM=0
EXISTING=""

if [[ "$DRY_RUN" != "1" ]]; then
  command -v gh >/dev/null || { echo "gh CLI not found: https://cli.github.com"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Run 'gh auth login' first."; exit 1; }
  echo "Target repo: $(gh api 'repos/{owner}/{repo}' --jq .full_name)"
  EXISTING="$(gh issue list --state all --limit 1000 --json number,title \
    --jq '.[] | "\(.number)\t\(.title)"')"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
label() {
  if [[ "$DRY_RUN" == "1" ]]; then echo "[dry-run] label: $1"; return; fi
  gh label create "$1" --color "$2" --description "$3" --force >/dev/null
  echo "label: $1"
}

milestone() {
  local title="$1" due="$2" desc="$3"
  if [[ "$DRY_RUN" == "1" ]]; then echo "[dry-run] milestone: $title (due $due)"; return; fi
  if gh api "repos/{owner}/{repo}/milestones?state=all&per_page=100" --jq '.[].title' \
      | grep -Fxq "$title"; then
    echo "milestone exists: $title"
  else
    gh api "repos/{owner}/{repo}/milestones" \
      -f title="$title" -f due_on="$due" -f description="$desc" >/dev/null
    echo "milestone: $title"
  fi
}

# usage: issue VAR "Title" "label1,label2" "Milestone" "$DEP1 $DEP2" <<'EOF' ... EOF
issue() {
  local var="$1" title="$2" labels="$3" ms="$4" deps="${5:-}"
  local body num url d
  body="$(cat)"
  if [[ -n "$deps" ]]; then
    body+=$'\n\n**Depends on:**'
    for d in $deps; do body+=" #$d"; done
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    FAKE_NUM=$((FAKE_NUM + 1)); num="$FAKE_NUM"
    echo "[dry-run] #$num  $title  [$labels]  ($ms)${deps:+  deps: $deps}"
  else
    num="$(printf '%s\n' "$EXISTING" | awk -F'\t' -v t="$title" '$2 == t { print $1; exit }')"
    if [[ -n "$num" ]]; then
      echo "exists:  #$num $title"
    else
      url="$(gh issue create --title "$title" --label "$labels" --milestone "$ms" \
        --body-file - <<< "$body")"
      num="${url##*/}"
      echo "created: #$num $title"
      sleep 1   # stay under GitHub's content-creation rate limit
    fi
  fi
  printf -v "$var" '%s' "$num"
}

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------
label "track-a-data-eval"    "1d76db" "Track A: data, model loading, metrics, baseline"
label "track-b-whitebox"     "d93f0b" "Track B: white-box gradient attacks (FGSM/BIM/PGD)"
label "track-c-transfer" "0e8a16" "Track C: CLIP-based transfer attacks and second-VLM stretch"
label "track-d-defenses"     "5319e7" "Track D: preprocessing defenses and adaptive attacks"
label "track-e-integration"  "fbca04" "Track E: infra, experiment grid, analysis, stretch goal"
label "setup"                "c5def5" "Repo, environment, compute"
label "attack"               "b60205" "Attack implementation"
label "defense"              "0052cc" "Defense implementation"
label "eval"                 "bfdadc" "Evaluation and metrics"
label "experiment"           "006b75" "Running experiments and analysis"
label "writing"              "fef2c0" "Final paper"
label "presentation"         "f9d0c4" "Slides and talk"
label "critical-path"        "e11d21" "Other issues are blocked on this"
label "stretch"              "cccccc" "Only if time allows"

# ---------------------------------------------------------------------------
# Milestones (due 11:59pm Pacific, expressed in UTC)
# ---------------------------------------------------------------------------
M1="M1: Setup & Baselines"
M2="M2: Attacks & Defense Modules"
M3="M3: Experiment Grid & Analysis"
M4="M4: Presentation"
M5="M5: Final Paper"
milestone "$M1" "2026-11-25T07:59:00Z" "Due Tue Nov 24. Repo, compute check, data, clean baseline, defense modules."
milestone "$M2" "2026-12-02T07:59:00Z" "Due Tue Dec 1 (Thanksgiving week). All attacks implemented, defenses costed, runner ready."
milestone "$M3" "2026-12-07T07:59:00Z" "Due Sun Dec 6. Adaptive attacks, full grid, figures, stretch goals."
milestone "$M4" "2026-12-11T07:59:00Z" "Due Thu Dec 10. Presentation plus methodology drafts."
milestone "$M5" "2026-12-12T07:59:00Z" "Due Fri Dec 11. Final 6-page paper submitted."

# =============================================================================
# M1: Setup & Baselines
# =============================================================================
issue SCAFFOLD "Set up repo structure and Python environment" \
  "track-e-integration,setup,critical-path" "$M1" <<'EOF'
## Goal
One shared skeleton so everyone writes code in the same place from day one.

## Tasks
- [ ] Folders: `src/{models,attacks,defenses,eval}`, `configs/`, `scripts/`, `notebooks/`, `results/`, `data/`
- [ ] `requirements.txt` with pinned versions: torch, transformers, accelerate, bitsandbytes, open_clip_torch, datasets, pillow, numpy, pandas, matplotlib, pyyaml, pycocoevalcap
- [ ] `.gitignore` for `data/`, `results/`, checkpoints, HF cache
- [ ] Workflow: one branch per issue, PR into `main` with `Closes #N`, one reviewer
- [ ] README stub with setup steps for the course JupyterLab GPUs

## Done when
A teammate can clone, install, and `import src` on JupyterLab.
EOF

issue GPU_PROFILE "Profile hardware and pick the LLaVA precision for the whole project" \
  "track-b-whitebox,setup,critical-path" "$M1" <<'EOF'
## Goal
JupyterHub sessions have 16 GB of system RAM; GPU VRAM is unconfirmed. White-box attacks need gradients through all of LLaVA-1.5-7B (~14 GB of weights in fp16). Decide on day 1 which precision everyone uses.

## Tasks
- [ ] Run `nvidia-smi` and `free -h` on JupyterHub; post GPU model, VRAM, RAM, and whether sessions can run in parallel
- [ ] Always load with `low_cpu_mem_usage=True, device_map="cuda:0"` so weights never sit fully in the 16 GB of system RAM
- [ ] Decision rule:
  - VRAM >= 24 GB: fp16
  - VRAM ~16 GB: 4-bit NF4 via bitsandbytes, `bnb_4bit_compute_dtype=torch.float16` (T4/V100 have no bf16), `llm_int8_skip_modules=["vision_tower", "multi_modal_projector"]` to keep the vision path full precision
- [ ] With the chosen config: `model.requires_grad_(False)`, `gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})`; measure peak memory for `generate` and for one forward + backward w.r.t. the image
- [ ] Record seconds per forward+backward step (feeds the grid budget)
- [ ] Put the loading config in `src/models/llava.py` so every experiment uses identical precision
- [ ] Fallback if JupyterHub is too slow: test the same notebook on Kaggle or Colab free GPUs and note current quotas

## Done when
Numbers and the precision decision posted as a comment. If 4-bit is used, note it for the paper: we attack a quantized LLaVA, applied identically across all conditions.
EOF

issue DATASET "Pick primary dataset and build a fixed evaluation subset" \
  "track-a-data-eval,eval,critical-path" "$M1" <<'EOF'
## Goal
The proposal lists VQA v2, OK-VQA, Flickr8k/30k. Pick one primary dataset so the attack x defense grid stays manageable.

## Tasks
- [ ] Recommendation: VQA v2 val as primary (short answers make ASR unambiguous); captioning only if time allows
- [ ] Sample a fixed subset with a seed: ~200 examples for experiments plus a separate ~50-example dev split for debugging (sized for limited compute; grow it only if time allows)
- [ ] Download only the subset images individually, not the full COCO val2014 archive (several GB)
- [ ] Save `data/subset_vqav2.json` with image_id, question_id, question, all 10 human answers
- [ ] Commit the ID list (not images) so everyone evaluates identical examples
- [ ] Loader returns `(image, question, answers)`

## Done when
Subset file committed and loader merged.
EOF

issue OVERLEAF "Set up paper skeleton in Overleaf" \
  "track-c-transfer,writing" "$M1" <<'EOF'
## Goal
Writing can start in parallel with code.

## Tasks
- [ ] Use the course template (6 pages + references)
- [ ] Sections: Abstract, Problem Statement & Motivation, Related Work, Methodology, Experiments, Results, Conclusions, Individual Contributions, References
- [ ] Shared `.bib` with all proposal references [1]-[12] plus the defense/adaptive-attack papers: Guo et al. 2018, Xu et al. 2018, Xie et al. 2018, Athalye et al. 2018
- [ ] Page budget per section in a comment at the top (contributions paragraph counts toward the 6 pages)
- [ ] Link the Overleaf project in the README

## Done when
Skeleton compiles and every member has edit access.
EOF

issue JPEG "Defense module interface and JPEG compression" \
  "track-d-defenses,defense" "$M1" "$SCAFFOLD" <<'EOF'
## Goal
Common interface for all preprocessing defenses, starting with JPEG.

## Tasks
- [ ] Interface: `defend(x: Tensor in [0,1], shape (B,3,H,W)) -> Tensor in [0,1]`, applied before the model wrapper
- [ ] JPEG compression at quality {50, 75, 90} (Guo et al. 2018)
- [ ] Round-trip through PIL on the 8-bit image
- [ ] Unit test: shape, dtype, and range preserved

## Done when
Merged with tests. No model needed to build this.
EOF

issue BLUR_BITS "Implement Gaussian blur and bit-depth reduction defenses" \
  "track-d-defenses,defense" "$M1" "$JPEG" <<'EOF'
## Tasks
- [ ] Gaussian blur, sigma in {0.5, 1.0, 1.5}, kernel size derived from sigma
- [ ] Bit-depth reduction to {3, 4, 5} bits (feature squeezing, Xu et al. 2018)
- [ ] Same interface as JPEG; unit tests

## Done when
Merged with tests.
EOF

issue RESIZE "Implement random resizing and padding defense" \
  "track-d-defenses,defense" "$M1" "$JPEG" <<'EOF'
## Tasks
- [ ] Randomly rescale (e.g., scale in [0.9, 1.1]), then random-pad back to 336x336 (Xie et al. 2018)
- [ ] Seedable; log the seed with results
- [ ] Document how stochasticity is handled in eval (fixed seed, or mean over a few runs)

## Done when
Merged with tests.
EOF

issue CLEAN_INFER "Build LLaVA-1.5-7B clean inference pipeline" \
  "track-a-data-eval,setup,critical-path" "$M1" "$SCAFFOLD $GPU_PROFILE" <<'EOF'
## Tasks
- [ ] Wrapper `answer(image, question) -> str` using HF `LlavaForConditionalGeneration` + `AutoProcessor`, loaded with the precision decided in the profiling issue
- [ ] Prompt: `USER: <image>\n{question}\nAnswer the question using a single word or phrase. ASSISTANT:`
- [ ] Greedy decoding, small `max_new_tokens` (~10), fixed seed
- [ ] Batch size 1 by default; batching only if memory allows
- [ ] Run on the dev split and eyeball outputs

## Done when
Wrapper merged and dev-split answers look sane.
EOF

issue METRICS "Implement VQA accuracy metric (optional captioning metrics)" \
  "track-a-data-eval,eval" "$M1" "$DATASET" <<'EOF'
## Tasks
- [ ] VQA v2 accuracy: `min(#matching human answers / 3, 1)` with standard answer normalization (case, punctuation, articles, number words)
- [ ] Unit tests on hand-made cases
- [ ] Optional: CIDEr and BLEU-4 via `pycocoevalcap` if captioning stays in scope

## Done when
`vqa_accuracy(pred, answers)` merged with tests.
EOF

issue ASR_SCHEMA "Define attack success rate (ASR) and results logging format" \
  "track-a-data-eval,eval,critical-path" "$M1" "$METRICS" <<'EOF'
## Goal
Every experiment writes results the same way so the whole grid aggregates with one script.

## Tasks
- [ ] Untargeted ASR: fraction of clean-correct examples that become incorrect under attack (report the denominator)
- [ ] Targeted ASR: fraction whose normalized output matches the target string
- [ ] Also report accuracy under attack over all examples
- [ ] Note for the paper: Paredes La Torre measures ASR on agents in a simulated e-commerce environment, not VQA, so our numbers are not directly comparable to their 52.6/53.8/66.9%. Write down their definition and ours side by side
- [ ] JSONL schema, one row per example: `example_id, model, vision_encoder, attack, eps, steps, defense, defense_params, adaptive, prediction, vqa_acc, target_hit, latency_ms, seed`
- [ ] `scripts/aggregate.py`: JSONL -> summary CSV

## Done when
Schema documented in README and aggregator merged.
EOF

issue BASELINE "Run clean baseline: accuracy and inference time (no attack, no defense)" \
  "track-a-data-eval,eval" "$M1" "$CLEAN_INFER $METRICS $ASR_SCHEMA" <<'EOF'
## Tasks
- [ ] Clean accuracy on the full subset
- [ ] Latency: warm-up runs, `torch.cuda.synchronize()`, median per example
- [ ] Save JSONL + summary in the agreed schema
- [ ] Sanity check against LLaVA-1.5-7B's published VQA v2 test-dev score (78.5). Val-subset differences are expected; a large gap usually means a prompt or preprocessing bug (4-bit may cost a point or two)

## Done when
Baseline numbers committed and posted as a comment.
EOF

issue DIFF_PREP "Differentiable image preprocessing wrapper for attacks" \
  "track-b-whitebox,attack,critical-path" "$M1" "$CLEAN_INFER" <<'EOF'
## Goal
Attacks perturb the image in [0,1] pixel space, not the normalized tensor, so epsilon means the same thing across every attack and defense.

## Tasks
- [ ] Offline: resize/crop each image to 336x336 exactly as the HF processor does; store as uint8
- [ ] Torch path: `x in [0,1] (B,3,336,336)` -> CLIP mean/std normalization -> `pixel_values`
- [ ] Equivalence check: wrapper path and processor path give identical answers on the dev split
- [ ] Helper to quantize adversarial images to 8-bit and save PNG; all attacked results are evaluated from saved PNGs

## Done when
Merged and equivalence check passes.
EOF

issue SURROGATES "Set up surrogate CLIP encoders for transfer attacks" \
  "track-c-transfer,attack" "$M1" "$SCAFFOLD" <<'EOF'
## Threat model note
LLaVA-1.5 keeps its CLIP ViT-L/14-336 frozen, so crafting on that exact encoder is **gray-box** (encoder known), not black-box. Use at least one different encoder for a true transfer setting.

## Tasks
- [ ] Gray-box surrogate: `openai/clip-vit-large-patch14-336` (same weights as LLaVA's vision tower)
- [ ] Black-box surrogates: e.g., OpenAI CLIP ViT-B/16 and an open_clip LAION ViT-L/14 (these also form the ensemble for the Hu et al. attack)
- [ ] Feature helper returning pooled image embedding and penultimate-layer patch features (LLaVA consumes layer -2 patch features)
- [ ] Differentiable resize from the 336px image to each surrogate's input size

## Done when
Helper merged; all surrogates load on JupyterLab.
EOF

# =============================================================================
# M2: Attacks & Defense Modules
# =============================================================================
issue LOSSES "Implement attack loss functions for LLaVA (untargeted and targeted)" \
  "track-b-whitebox,attack" "$M2" "$DIFF_PREP" <<'EOF'
## Tasks
- [ ] Untargeted: maximize cross-entropy of the most common ground-truth answer tokens (teacher forcing on prompt + answer, loss masked to answer tokens)
- [ ] Targeted: minimize cross-entropy of a fixed target string; document the choice
- [ ] Returns loss and gradient w.r.t. `x`; params frozen
- [ ] Sanity check: gradient is non-zero and loss responds to changes in `x`

## Done when
`loss_fn(x, question, answer, mode)` merged.
EOF

issue FGSM "Implement FGSM attack" \
  "track-b-whitebox,attack" "$M2" "$LOSSES" <<'EOF'
## Tasks
- [ ] `x_adv = clip(x + eps * sign(grad_x L), 0, 1)` (Goodfellow et al. 2015)
- [ ] Shared `Attack` interface: `run(x, question, answer) -> x_adv`, reused by BIM/PGD
- [ ] eps in {4, 8, 16}/255 (add 2/255 only if time allows)
- [ ] Test on dev split

## Done when
Merged and FGSM lowers dev accuracy at eps = 8/255.
EOF

issue BIM "Implement BIM attack" \
  "track-b-whitebox,attack" "$M2" "$FGSM" <<'EOF'
## Tasks
- [ ] Iterative FGSM with step alpha = 1/255, projected to the eps-ball each step (Kurakin et al. 2016)
- [ ] Steps = min(eps*255 + 4, 1.25*eps*255) per Kurakin et al., unless Paredes La Torre's code (https://github.com/AlejandroParedesLT/vlm_attacks) uses different settings; if so, match theirs and note it
- [ ] Log loss per step for debugging

## Done when
Merged; ASR >= FGSM at the same eps on the dev split.
EOF

issue PGD "Implement PGD attack" \
  "track-b-whitebox,attack,critical-path" "$M2" "$FGSM" <<'EOF'
## Tasks
- [ ] Uniform random start in the eps-ball, then projected iterative steps (Madry et al. 2018)
- [ ] Configurable steps with default 10 for the grid (20+ only for spot checks), step size (e.g., 2.5*eps/steps), no restarts by default
- [ ] Match the PGD settings in Paredes La Torre's code (https://github.com/AlejandroParedesLT/vlm_attacks) for comparability

## Done when
Merged; loss curve plateaus; ASR >= BIM on the dev split.
EOF

issue WB_SWEEP "Run white-box epsilon sweep and attack sanity checks" \
  "track-b-whitebox,experiment" "$M2" "$BIM $PGD $BASELINE" <<'EOF'
## Tasks
- [ ] FGSM / BIM / PGD x eps {4, 8, 16}/255 on the subset, no defense
- [ ] Save every adversarial image as PNG: defenses are applied to these saved images later, so non-adaptive attacks are generated only once
- [ ] Sanity checks: ASR rises with eps; iterative >= single-step; eps = 0 reproduces clean accuracy; random noise of the same eps barely moves accuracy
- [ ] Save a few clean vs adversarial image pairs with model answers for slides and paper

## Done when
JSONL results committed and an ASR-vs-eps plot posted.
EOF

issue EMB_ATTACK "Implement CLIP embedding-disruption attack" \
  "track-c-transfer,attack" "$M2" "$SURROGATES $DIFF_PREP" <<'EOF'
## Tasks
- [ ] PGD in pixel space maximizing `1 - cos(f(x + delta), f(x))` on surrogate features
- [ ] Two variants: pooled image embedding vs penultimate patch features
- [ ] Same eps grid as the white-box attacks
- [ ] Save adversarial PNGs per surrogate for transfer evaluation

## Done when
Merged; cosine similarity on the surrogate itself drops substantially.
EOF

issue SPECTRAL "Implement the CLIP-based spectral attack from Paredes La Torre" \
  "track-c-transfer,attack" "$M2" "$EMB_ATTACK" <<'EOF'
## Tasks
- [ ] Read the methods section of arXiv:2603.16960; write down the exact objective, hyperparameters, and eps
- [ ] Code is released at https://github.com/AlejandroParedesLT/vlm_attacks: start from it, adapt to our wrapper and VQA subset
- [ ] Implement as an option of the embedding attack
- [ ] Where the paper is ambiguous, document assumptions in a comment (needed for the methodology section)

## Done when
Merged with the written spec in the docstring.
EOF

issue TRANSFER_EVAL "Evaluate transfer of CLIP-crafted attacks to LLaVA" \
  "track-c-transfer,experiment" "$M2" "$EMB_ATTACK $SPECTRAL $BASELINE" <<'EOF'
## Tasks
- [ ] Run saved adversarial images (gray-box and black-box surrogates, both variants, all eps) through LLaVA
- [ ] Report ASR and accuracy under attack per surrogate
- [ ] Put the 66.9% spectral-attack ASR from Paredes La Torre next to ours, noting their e-commerce agent setting vs our VQA setting

## Done when
JSONL results committed and a summary table posted.
EOF

issue ENSEMBLE "Implement surrogate-ensemble targeted transfer attack (Hu et al.)" \
  "track-c-transfer,attack" "$M2" "$SURROGATES $EMB_ATTACK" <<'EOF'
## Goal
Second transfer attack from the proposal references. Hu et al. (arXiv:2505.01050) craft targeted perturbations on an ensemble of open-source, mostly CLIP-based, encoders and show they transfer to black-box VLMs.

## Tasks
- [ ] Read the method section; write down the loss, ensemble members, eps, and steps
- [ ] Implement a targeted version: pull the adversarial image's embedding toward a target (target image or target text embedding), averaged over the surrogate ensemble
- [ ] Choose target concepts that are easy to check in VQA answers (e.g., make the model answer about a different object)
- [ ] Save adversarial PNGs for transfer to LLaVA
- [ ] Document any simplifications vs the paper (needed for methodology)

## Done when
Merged; targeted embedding similarity on the surrogates rises clearly.
EOF

issue DEF_COST "Measure clean-accuracy and latency cost of each defense" \
  "track-d-defenses,experiment" "$M2" "$BLUR_BITS $RESIZE $BASELINE" <<'EOF'
## Tasks
- [ ] Run every defense setting on the clean subset (no attack)
- [ ] Pick 1-2 settings per defense with acceptable clean drop (e.g., <= 3 points) for the full grid
- [ ] Record added latency per defense

## Done when
Table posted; chosen settings written into `configs/`.
EOF

issue RUNNER "Experiment config and grid runner with runtime estimate" \
  "track-e-integration,experiment,critical-path" "$M2" "$ASR_SCHEMA $DIFF_PREP $JPEG $GPU_PROFILE" <<'EOF'
## Tasks
- [ ] YAML configs: model/encoder, attack + params, defense + params, adaptive flag, subset, seed
- [ ] `scripts/run_experiment.py --config ...` writes JSONL in the agreed schema
- [ ] Resumable: skip example_ids already in the output file (JupyterLab sessions die)
- [ ] Non-adaptive attacks: generate once, then evaluate every defense on the saved images (inference only)
- [ ] Adaptive attacks: the only part regenerated per defense
- [ ] Estimate total GPU hours from the measured step time. Target plan: ~200 examples, eps {4, 8, 16}/255, PGD-10, adaptive at 8/255 only, EOT k = 5 (roughly 150 gradient steps per example). Trim further if the estimate runs past Dec 6
- [ ] Split runs across members' sessions in parallel (and Kaggle/Colab if needed); write the split as a comment

## Done when
Runner merged; grid plan and runtime estimate posted as a comment.
EOF

issue CTP_FEAS "[Stretch] CTP backdoor: read paper and assess feasibility" \
  "track-e-integration,attack,stretch" "$M2" "$BASELINE" <<'EOF'
## Tasks
- [ ] Read Shen et al., Concept-Guided Backdoor Attack on VLMs (arXiv:2512.00713): trigger construction, poisoning rate, fine-tuning setup, compute
- [ ] Estimate whether a QLoRA fine-tune of LLaVA-1.5-7B on a small poisoned set fits on the available GPU in about 2 days of compute. With 16 GB this is likely a no-go; decide early rather than late
- [ ] Go/no-go by Dec 1. If no-go, write one paragraph for the paper's future-work discussion

## Done when
Go/no-go comment posted.
EOF

# =============================================================================
# M3: Experiment Grid & Analysis
# =============================================================================
issue QWEN "[Stretch] Repeat key attacks and defenses on Qwen2.5-VL-7B" \
  "track-c-transfer,experiment,stretch" "$M3" "$TRANSFER_EVAL $ENSEMBLE $DEF_COST" <<'EOF'
## Goal
Paredes La Torre found Qwen2.5-VL-7B far more robust than LLaVA under the same attacks. Its vision encoder is not OpenAI CLIP, so CLIP-crafted attacks are a true black-box transfer here.

## Tasks
- [ ] Load `Qwen/Qwen2.5-VL-7B-Instruct` (4-bit if VRAM is ~16 GB); fix the input resolution (it uses dynamic resolution by default) so results are comparable
- [ ] Clean accuracy on the same subset
- [ ] Transfer the saved spectral and ensemble adversarial images; run with and without the chosen preprocessing defenses
- [ ] White-box PGD only if memory allows

## Done when
Comparison table posted, or issue closed as "not run" with the reason.
EOF

issue BPDA "Adaptive attack: BPDA through JPEG and bit-depth reduction" \
  "track-d-defenses,attack" "$M3" "$DEF_COST $PGD" <<'EOF'
## Goal
Defenses that break gradients can look strong only because the attacker ignores them. Test them against an attacker who accounts for the preprocessing step.

## Tasks
- [ ] BPDA (Athalye et al. 2018): forward through the defense, backward as identity (straight-through)
- [ ] Wrap PGD so the defense sits inside the attack loop
- [ ] Run at eps = 8/255 only unless time allows more
- [ ] Compare ASR: standard PGD + defense vs BPDA-PGD + defense

## Done when
Merged and results posted. Defenses getting much weaker here is a result, not a bug.
EOF

issue EOT "Adaptive attack: EOT for random resizing and Gaussian blur" \
  "track-d-defenses,attack" "$M3" "$DEF_COST $PGD" <<'EOF'
## Tasks
- [ ] Random resize: Expectation over Transformation, averaging gradients over k samples of the random transform (k = 5 to fit the compute budget)
- [ ] Run at eps = 8/255 only unless time allows more
- [ ] Gaussian blur is differentiable: include it directly in the forward pass
- [ ] Compare ASR: standard vs adaptive

## Done when
Merged and results posted.
EOF

issue GRID_WB "Run grid: white-box attacks x preprocessing defenses" \
  "track-e-integration,experiment" "$M3" "$RUNNER $WB_SWEEP $BPDA $EOT" <<'EOF'
## Tasks
- [ ] FGSM / BIM / PGD x chosen eps x {none, JPEG, blur, bit-depth, resize} x {standard, adaptive}
- [ ] Run through the runner; check for missing rows before aggregating
- [ ] Clean accuracy and latency per defense included in the same table

## Done when
Aggregated CSV committed.
EOF

issue GRID_TR "Run grid: transfer attacks x preprocessing defenses" \
  "track-e-integration,experiment" "$M3" "$RUNNER $TRANSFER_EVAL $ENSEMBLE $DEF_COST $BPDA $EOT" <<'EOF'
## Tasks
- [ ] Spectral (gray-box and black-box surrogates) and surrogate-ensemble adversarial images x preprocessing defenses
- [ ] Adaptive variants: regenerate transfer attacks with the defense inside the surrogate loop (BPDA/EOT), so the attacker knows preprocessing is applied

## Done when
Aggregated CSV committed.
EOF

issue FIGURES "Results tables and figures for paper and slides" \
  "track-e-integration,experiment" "$M3" "$GRID_WB $GRID_TR" <<'EOF'
## Tasks
- [ ] Main table: clean accuracy, ASR per attack x defense (standard and adaptive), latency
- [ ] Figure: ASR vs eps per attack, no defense
- [ ] Figure: clean accuracy vs ASR trade-off per defense setting
- [ ] Figure: clean/adversarial image examples with model answers
- [ ] Everything generated by `scripts/make_figures.py`, exported as PDF

## Done when
Figures in Overleaf and in the slides folder.
EOF

issue CTP_RUN "[Stretch] CTP backdoor: small-scale poisoning vs preprocessing" \
  "track-e-integration,attack,stretch" "$M3" "$CTP_FEAS $DEF_COST" <<'EOF'
## Only if the feasibility issue is a go.

## Tasks
- [ ] Poison a small fine-tuning set following Shen et al.; LoRA fine-tune LLaVA
- [ ] Measure ASR on concept-trigger inputs and clean accuracy, with and without each preprocessing defense
- [ ] Hypothesis from the proposal: input preprocessing does not remove a semantic backdoor

## Done when
Results table posted, or issue closed as "not run" with the reason.
EOF

issue W_PROBLEM "Draft problem statement and motivation (conceptual + mathematical)" \
  "track-b-whitebox,writing" "$M3" "$OVERLEAF" <<'EOF'
## Tasks
- [ ] Conceptual: why VLM robustness matters, what preprocessing defenses promise, what prior work leaves open
- [ ] Mathematical: threat model, `max_{||delta||_inf <= eps} L(f(T(x + delta)), y)` with T the preprocessing defense; untargeted vs targeted; ASR definition
- [ ] Target ~0.75 page

## Done when
Drafted in Overleaf.
EOF

issue W_RELATED "Draft related work section" \
  "track-c-transfer,writing" "$M3" "$OVERLEAF" <<'EOF'
## Tasks
- [ ] Attacks on VLMs: Paredes La Torre, Hu et al., Image Hijacks, SGA, Jailbreak in Pieces (pull from the team's candidate paper table)
- [ ] Input-transformation defenses and how adaptive attacks break them: Guo, Xu, Xie, Athalye
- [ ] One or two sentences on adversarial fine-tuning (TeCoA, Robust CLIP) as an alternative defense we chose not to pursue
- [ ] Backdoors: Shen et al. (CTP)
- [ ] Target ~0.75 page

## Done when
Drafted with all citations in the `.bib`.
EOF

# =============================================================================
# M4: Presentation (Dec 10) + methodology drafts
# =============================================================================
issue W_METH_WB "Draft methodology: white-box attacks" \
  "track-b-whitebox,writing" "$M4" "$WB_SWEEP $OVERLEAF" <<'EOF'
## Tasks
- [ ] FGSM / BIM / PGD equations, answer-token loss, pixel-space eps, settings table
- [ ] Enough detail that a reader could reimplement it (course requirement)

## Done when
Drafted in Overleaf.
EOF

issue W_METH_TR "Draft methodology: CLIP-based transfer attacks" \
  "track-c-transfer,writing" "$M4" "$TRANSFER_EVAL $ENSEMBLE $OVERLEAF" <<'EOF'
## Tasks
- [ ] Surrogate list and the gray-box vs black-box distinction
- [ ] Spectral attack objective (Paredes La Torre) and any assumptions we made
- [ ] Surrogate-ensemble targeted objective (Hu et al.) and simplifications vs the paper

## Done when
Drafted in Overleaf.
EOF

issue W_METH_DEF "Draft methodology: preprocessing defenses and adaptive attacks" \
  "track-d-defenses,writing" "$M4" "$BPDA $EOT $OVERLEAF" <<'EOF'
## Tasks
- [ ] Each defense with chosen parameters and why
- [ ] BPDA and EOT explained with equations

## Done when
Drafted in Overleaf.
EOF

issue W_EVALSETUP "Draft evaluation setup: dataset, metrics, compute" \
  "track-a-data-eval,writing" "$M4" "$BASELINE $OVERLEAF" <<'EOF'
## Tasks
- [ ] Dataset, subset sampling, prompt format
- [ ] Metrics: VQA accuracy, ASR definitions, latency measurement method
- [ ] Hardware, model precision (fp16 or 4-bit), seeds, runtimes

## Done when
Drafted in Overleaf.
EOF

issue SLIDES "Build presentation slide deck" \
  "track-d-defenses,presentation" "$M4" "$FIGURES" <<'EOF'
## Tasks
- [ ] Use the course presentation template
- [ ] Outline: problem, threat model, methods, setup, results (main table + 2 figures), takeaways, limitations
- [ ] Confirm the time limit from the course guidelines and size the deck to it
- [ ] Each member drafts the slides for their own work

## Done when
Full deck ready by Dec 9.
EOF

issue REHEARSAL "Presentation rehearsal and timing" \
  "track-d-defenses,presentation" "$M4" "$SLIDES" <<'EOF'
## Tasks
- [ ] Full timed run-through by the evening of Dec 9
- [ ] Assign speakers per section
- [ ] Prep likely questions: why preprocessing, adaptive attacks, gray-box vs black-box, subset size

## Done when
Rehearsal done and deck final.
EOF

# =============================================================================
# M5: Final Paper (Dec 11)
# =============================================================================
issue W_RESULTS "Write experiments and results section" \
  "track-e-integration,writing" "$M5" "$FIGURES" <<'EOF'
## Tasks
- [ ] Main table and figures with discussion: which attacks get through the preprocessing defense, how much adaptive attacks recover, white-box vs transfer, clean-accuracy cost, latency (plus Qwen2.5-VL if the stretch ran)
- [ ] Parameter tuning and design choices (course requirement)
- [ ] Comparison with Paredes La Torre's reported ASRs, clearly caveated (agent setting vs VQA)

## Done when
Drafted with final numbers that match the committed CSVs.
EOF

issue W_ABSTRACT "Write abstract, conclusions, and individual contributions paragraph" \
  "track-a-data-eval,writing" "$M5" "$W_RESULTS" <<'EOF'
## Tasks
- [ ] Abstract
- [ ] Conclusions: what we learned, strengths and weaknesses of each method, project successes and failures (all asked for in the rubric)
- [ ] Contributions paragraph: one line per member, plus anything that took much more or less time than expected

## Done when
Drafted, and each member has confirmed their contribution line.
EOF

issue README "Write reproduction instructions in README" \
  "track-a-data-eval,setup" "$M5" "$GRID_WB $GRID_TR" <<'EOF'
## Tasks
- [ ] Environment setup and data download
- [ ] Exact commands to reproduce each table and figure
- [ ] Hardware used and approximate runtimes

## Done when
Someone outside this track follows the README on a fresh clone and reproduces the clean baseline.
EOF

issue FINAL "Final paper pass: page limit, references, proofread, submit" \
  "track-e-integration,writing,critical-path" "$M5" \
  "$W_PROBLEM $W_RELATED $W_METH_WB $W_METH_TR $W_METH_DEF $W_EVALSETUP $W_RESULTS $W_ABSTRACT" <<'EOF'
## Tasks
- [ ] 6 pages + references, contributions paragraph inside the 6
- [ ] Every figure and table referenced in the text; numbers match the CSVs
- [ ] `.bib` complete and consistent
- [ ] AI-assistance acknowledgment if the course requires it (the proposal included one)
- [ ] Submit PDF by Dec 11, 11:59pm

## Done when
Submitted.
EOF

echo
echo "Done. Tip: add these issues to a GitHub Project board grouped by milestone or track."
