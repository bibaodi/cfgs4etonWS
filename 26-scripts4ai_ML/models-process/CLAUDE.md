# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Scripts that take trained models out of `/train/history_train/` and publish them as downloadable
packages for a handheld ultrasound app. The app fetches a manifest JSON from S3, compares MD5s
against local files, and downloads a versioned zip of `.tflite` + `.xml` model files.

This directory is one subtree of the `00cfgs4etonWS` monorepo (git root is
`/home/eton/00-srcs/00cfgs4etonWS`). `guidance-files/` is a parallel twin of this directory for
guidance videos — same two-upload-script pattern, different bucket prefix.

## Commands

There is no build, test, or lint step. All scripts are run directly and are interactive
(`read -r -p` prompts); run them from this directory.

```bash
# 1. Validate, generate validation.json, zip, and write the updated manifest.
#    Run from INSIDE the package folder, which must be named modelsV<next version>
#    and already contain the new .tflite/.xml pair.
cd ~/Downloads/modelsV2.9.4
/path/to/generate-validation4ModelsPackage2S3.py

# Interactive prompts: zip creation, manifest append, changelog text.
# Answer "n" at the zip prompt to run the validators only.

# Override the version, or bypass the folder-name check
./generate-validation4ModelsPackage2S3.py --version 2.9.5
./generate-validation4ModelsPackage2S3.py --skip-version-check

# 2. Upload the .zip and the manifest YOURSELF — the script does not upload.
./uploadNewModelsPackage2S3.sh ~/Downloads/modelsV2.9.4.zip
./updateS3ModelsInfo_forApp.sh ~/Downloads/models_information.json-for294

# 3. Inspect what is currently released
./show_modesl4APP.sh          # aws s3 ls s3://yingling-s3test/Models/

# 4. Pull a fresh training run into the current directory (see naming note below)
cd ~/Downloads/model_segCAPlaque_21yl26_S320-v01_i8
/path/to/copy_trained_models_here.sh res_...._20260515T1628_sz224
```

The Python script is stdlib-only — no venv, and **no `aws` CLI**, because it reads the manifest over
HTTPS. It does need network access to the `cn-north-1` endpoint. The upload shell scripts do require
the `aws` CLI; it is not on `PATH` in the default `trainLinkNet18_env` conda env, it lives at
`/mnt/datas/miniconda3/bin/aws`.

## Release workflow

The Python script stops at producing the `.zip` and the manifest JSON. Uploading is a separate,
manual step.

`main()` first resolves the release version from the **published** manifest, then validates, then
packages:

```
fetch_online_entries()      -> latest online is e.g. 2.9.3/293, so next is 2.9.4/294
folder-name check           -> must be modelsV2.9.4, else exit(1)
validate_file_pairs  →  validate_xml_locator_references  →  validate_presets_xml
                     →  generate_validation()  →  [zip]  →  [ModelsInfoBuilder.add_package()]
```

The version check runs *before* the validators so a mis-named folder fails before anything is
written. `manifest_url` is `BASE_URL` + `manifest_key`, i.e.
`https://yingling-s3test.s3.cn-north-1.amazonaws.com.cn/Models/models_information.json`.

`create_zip_package` writes `<folder>.zip` to the folder's **parent** (files at archive root, no
wrapping folder). `add_package` appends the new entry to the list fetched online and writes a
cumulative snapshot named `models_information.json-for<version_code>` into the same parent directory.

**The base list always comes from S3, never from local files.** `fetch_online_entries()` has no
fallback to the local `models_information.json-for*` snapshots: those can hold entries that were
never published (see Gotchas), which would skew the version this release is cut as. If the fetch
fails the script exits rather than guessing.

Two distinct upload scripts, both doing `aws s3 cp --acl public-read --metadata author=...,version=1.0`:

| Script | S3 destination |
| --- | --- |
| `uploadNewModelsPackage2S3.sh` | `Models/<basename of the file you pass>` — for the `.zip` |
| `updateS3ModelsInfo_forApp.sh` | `Models/models_information.json` (hardcoded name) — for the manifest |

So the manifest snapshot from step 1 is uploaded via `updateS3ModelsInfo_forApp.sh`, which renames
it to the canonical key. Uploading it via `uploadNewModelsPackage2S3.sh` would publish it under the
`...-for293` name instead, which the app will not find.

## Model package contract

A valid package is a flat directory of `.tflite` + `.xml` pairs plus `presets.xml`. The XML is the
source of truth for wiring — **XML filenames are not the model identifiers**:

```xml
<AiModel key="thyroid_yolo26V04" tflite="true" size="224" model_type="yolo26_seg">
    <Locator file="model_segThyNodu_yolo26_f16s224-v04.tflite">
        <Segment key="Nodule" threshold="0.5" color="0x40FF0000" />
    </Locator>
</AiModel>
```

- `AiModel/@key` is the model identifier the app uses (e.g. `thyroid_yolo26V04`, `fat221112`,
  `imt_linknet`) and is frequently unrelated to the filename.
- `Locator/@file` names the actual `.tflite`; this is the only filename→model mapping.
- `presets.xml` maps app screens to keys via `<preset application="app_thyroid" model="thyroid_yolo26V04"/>`
  — it references `key`, never a filename. It is deliberately excluded from the `.xml` scans by
  filename check.

The three validators enforce, respectively: every `.tflite` has a same-named `.xml`; every
`Locator/@file` exists on disk and no two XMLs share an `AiModel/@key`; every `presets.xml`
`model=` resolves to some `AiModel/@key`. `.tflite` files not referenced by any `Locator` are
reported as warnings only, not errors.

## Zip / manifest versioning

The version is **derived from the published manifest, not from the folder name**: take the entry
with the highest `version_code` online and bump its patch component (`bump_patch`), so online
2.9.3 → next 2.9.4. The folder name is then *checked* against that (`modelsV2.9.4`) and a mismatch
is a hard error. `--version X.Y.Z` overrides the derivation, and `--skip-version-check` downgrades
the mismatch to a warning.

Zip filenames must contain a three-part version — `modelsV2.9.3.zip`. `parse_version` takes the
first `\d+.\d+.\d+` match and `version_code` is the digits concatenated, so `2.9.3` → `293`; the
manifest snapshot filename is keyed on that code. `version_string_to_code` is the single place that
concatenation rule lives, used by both `parse_version` and the version checks in `main()`.
`add_package` de-duplicates by `version_code` (a re-release of the same version replaces the old
entry rather than appending). Entries carry `model_xml_version` (default `"2.3"`) and `schema`
(default `2.0`) as constructor defaults in `ModelsInfoBuilder`.

Caveat: because `version_code` is concatenation rather than arithmetic, a two-digit component does
not round-trip — `2.9.10` → `2910`. Fine at current versions, but `--version` is the escape hatch.

### Inherited entry fields

Some entry fields are app-compatibility metadata that is *not* derived from the package and cannot
be recomputed by the script. `ModelsInfoBuilder.INHERITED_ENTRY_KEYS` lists them:

| key | example |
| --- | --- |
| `matching_channels` | `["yz", "bs", ""]` |
| `minimum_app_version` | `16031` |

`build_entry()` copies these from the previous release's entry (the highest `version_code` in the
manifest it fetched), so cutting a new version carries them forward. If the previous entry does not
have them, they are **omitted rather than invented** — which is why every release up to 291 lacks
them and 292 onwards have them.

To add another such field, append its name to `INHERITED_ENTRY_KEYS`; the copy loop picks it up with
no other change. If a release ever needs to *change* one of these values rather than carry it
forward, that needs a new flag — there is deliberately no CLI override yet.

`BASE_URL` for the entry `url` field is hardcoded to the China-region endpoint
`https://yingling-s3test.s3.cn-north-1.amazonaws.com.cn/Models/` — keep it in sync with the region
used when echoing public URLs in the upload scripts.

## Gotchas

- **`generate_validation()` includes every file, not just `.tflite`/`.xml`.** It skips only its own
  basename and `validation.json`, so anything else left in the package folder (a stale copy of an
  older validation script, edit backups, `.DS_Store`) lands in `validation.json`. Every historical
  package carries a frozen `generate-validation.py` that is included this way.
- **One manifest name, and it is spelled correctly.** The script reads `models_information.json`
  from S3 and writes its local snapshot as `models_information.json-for<code>` — the snapshot name
  is derived from `manifest_key`, so the file you upload and the object it replaces cannot drift
  apart. Historical files in the release workspace use the older misspelling
  (`models_infomations.json-for293b` and friends); those are pre-existing artifacts, not something
  the script produces any more.
- **Never reintroduce a local-manifest fallback.** The local snapshots drifted from S3 once already:
  `models_infomations.json-for293b` contains a `modelsV2.9.4` / `version_code 294` entry that was
  never published — it came from a package cut as 2.9.4 and later renamed down to `modelsV2.9.3b`.
  The old `_load_entries()` scan picked that up and would have computed the next release from it.
  That is why the base list now comes from S3 only.
- **`copy_trained_models_here.sh` names outputs after the CWD**, copying `xinmy_multi.pt`/`.tflite`
  from `/train/history_train/<ResultName>/` to `./<current-dir-name>.pt`/`.tflite`. It needs the
  directory name to equal the intended model name (`Locator/@file` basename, and/or the model key).
  It fully rewrites `md5sum.txt` (`>` truncate) on every run. `copy_train-logs.sh` likewise requires
  `./train-logs/` to already exist.
- Checksum the folder *after* the last file edit — `validation.json` and the manifest entries are
  built from live MD5s, and the validators run before any zip is written.
