# deploy_agent

`deploy_agent.sh` bootstraps, runs and archives the **Student Attendance Tracker** (`attendance_checker.py`). It deploys the project structure from `templates/`, starts the interactive marking session, and archives the session logs with timestamped filenames. If deployment is interrupted with Ctrl+C or Ctrl+Z, it zips the partial project and removes the incomplete directory.

Video walkthrough: TODO add link

## Requirements

- Bash
- `python3` (the script checks `python3 --version` before deploying)
- `zip` (Ubuntu: `sudo apt install zip`)

## Repository layout

```
deploy_agent_alustudent/
├── deploy_agent.sh
├── templates/              # unmodified source files
│   ├── attendance_checker.py
│   ├── assets.csv
│   └── config.json
└── README.md
```

## Usage

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

TODO: describe how a feature is selected (menu or flags) and show each option, for example:

| Feature | How to select |
|---------|---------------|
| 1. Deploy | TODO |
| 2. Run | TODO |
| 3. Archive logs | TODO |

## Feature 1: Deploy

1. **Pre-flight checks:** verifies `python3` (prints `python3 --version`) and `zip` are installed, and exits with a clear message if either is missing.
2. **Project name:** asks for a name and creates `attendance_tracker_<name>/`. If it already exists, TODO: describe the overwrite prompt and the abort behaviour.
3. **Files:** copies `attendance_checker.py` and `config.json` from `templates/` and builds `Helpers/assets.csv` from one of two options:
   - **Option A, copy:** the header plus the first N students from `templates/assets.csv`.
   - **Option B, generate:** N new students from the sample names and emails in the script, with both counts at 0.
4. **Permissions:** `attendance_checker.py` is made executable (`chmod +x`) and `Helpers/config.json` is restricted to the owner (`chmod 600`).
5. **Thresholds:** optionally updates `warning` and `failure` (see below).
6. **Verification:** runs the application (Feature 2). A successful start proves the structure, roster and config work together.

Resulting structure:

```
attendance_tracker_<name>/
├── attendance_checker.py
├── Helpers/
│   ├── assets.csv
│   └── config.json
└── reports/
```

### total_sessions and the roster

`total_sessions` counts every session including today's, so it must equal the prior sessions in the roster plus one. The sample roster records 4 prior sessions per student, so Option A uses `total_sessions: 5`. A fresh Option B roster has no prior sessions, so it uses `total_sessions: 1`.

TODO: explain how the script sets `total_sessions` to 1 for Option B.

## Threshold update

When asked, enter new values for `warning` (default 75) and `failure` (default 50). TODO: describe the validation (empty input keeps the default? numeric only? 0–100? failure below warning?).

The script edits the deployed `Helpers/config.json` in place with `sed`, changing only the number on the `"warning":` and `"failure":` lines, so the file's formatting and key order stay the same.

## Feature 2: Run

Runs `python3 attendance_checker.py` from inside `attendance_tracker_<name>/`. The instructor marks each student present (`P`) or absent (`A`). The app updates the counts in `Helpers/assets.csv` and appends to `reports/attendance.log` and `reports/absent.log`.

## Feature 3: Archive logs

Each existing log is archived into its own folder with a timestamp (`YYYYMMDD_HHMMSS`) in the name, so every copy is unique and traceable:

```
attendance_tracker_<name>/archives/
├── attendance/attendance_20260927_143022.log
└── absent/absent_20260927_143022.log
```

The script prints the final path of each archived log. A missing log, such as `absent.log` when nobody was absent, is reported and skipped without stopping the script. TODO: state whether logs are moved or copied.

## Interrupt handling (Ctrl+C / Ctrl+Z)

During deployment, the script traps `SIGINT` (Ctrl+C) and `SIGTSTP` (Ctrl+Z). On either signal it:

1. prints that the deployment was interrupted,
2. zips whatever exists of `attendance_tracker_<name>/` into `attendance_tracker_<name>_archive.zip`,
3. deletes the incomplete directory,
4. exits cleanly.

The trap covers deployment only, not the marking session inside `attendance_checker.py`.

**To test it:** start a deploy, enter a project name, and press Ctrl+C (or Ctrl+Z) at the next prompt. Then check:

```bash
ls attendance_tracker_<name>              # gone
unzip -l attendance_tracker_<name>_archive.zip
```

TODO: list what the zip contains when interrupted at that point.

## Testing

TODO: describe how you tested, for example:

- Option A with 3 and with all 10 students, and Option B with 4 students: checked the structure, roster rows and `total_sessions`.
- Permissions checked with `ls -l` (`-rwx` on the app, `-rw-------` on `config.json`).
- Threshold update with valid, empty and non-numeric input, then checked `config.json` with `cat` and `python3 -m json.tool`.
- Deploying over an existing directory, answering both overwrite and abort.
- A run with nobody absent, followed by archiving, to check the missing `absent.log` case.
- Ctrl+C and Ctrl+Z during deployment.
