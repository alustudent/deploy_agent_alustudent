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
./deploy_agent.sh            # menu
./deploy_agent.sh deploy     # Feature 1 directly
./deploy_agent.sh --help
```

Pass a feature as the first argument, or run the script without one to pick it from a menu.

| Feature | How to select |
|---------|---------------|
| 1. Deploy | `./deploy_agent.sh deploy`, or menu option `1` |
| 2. Run | `./deploy_agent.sh run <name>`, or menu option `2` |
| 3. Archive logs | `./deploy_agent.sh archive <name>`, or menu option `3` |

If `run` or `archive` is given without a name, or picked from the menu, the script asks for the project name and checks that the project exists.

Projects are created next to `deploy_agent.sh`.

### Input validation

Every prompt validates its answer and allows **3 attempts**, showing how many are left after each invalid answer. After the third invalid answer the script exits with an error. If a partial project directory was already created, it is removed, so the next run starts clean.

## Feature 1: Deploy

1. **Pre-flight checks:** verifies `python3` (prints `python3 --version`) and `zip` are installed, and exits with a clear message if either is missing.
2. **Project name:** asks for a name and creates `attendance_tracker_<name>/`. Names may contain letters, digits, `-` and `_`. If the directory already exists, the script asks `Overwrite it? [y/N]`. Answering `y` replaces it. Answering `n` or pressing Enter aborts without touching it.
3. **Files:** copies `attendance_checker.py` and `config.json` from `templates/` and builds `Helpers/assets.csv` from one of two options:
   - **Option A, copy:** the header plus the first N students from `templates/assets.csv` (N from 1 to the number of students in the template, 10).
   - **Option B, generate:** N new students (1 to 100) from the sample names in the script, with both counts at 0. When N is more than the 10 sample names, the list repeats with a numeric suffix on the email (`amara.okafor2@example.com`), so emails stay unique.
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

For Option B, the script copies `config.json` unchanged and then edits only the `total_sessions` number with `sed`, the same way it updates the thresholds.

## Threshold update

The script asks `Update the attendance thresholds? [y/N]`. If you answer `y`, enter new values for `warning` (default 75) and `failure` (default 50):

- Both must be whole numbers. `warning` must be from 1 to 100, and `failure` from 0 to one below `warning`.
- Pressing Enter keeps the current value.
- Each value gets 3 attempts (see [Input validation](#input-validation)).

After the edit, the script checks that `config.json` is still valid JSON.

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

The script prints the final path of each archived log. A missing log, such as `absent.log` when nobody was absent, is reported and skipped without stopping the script. Logs are **moved**, not copied, so the next session starts with fresh logs in `reports/`. Both archived files share one timestamp, taken once per archive run.

## Interrupt handling (Ctrl+C / Ctrl+Z)

During deployment, the script traps `SIGINT` (Ctrl+C) and `SIGTSTP` (Ctrl+Z). On either signal it:

1. prints that the deployment was interrupted,
2. zips whatever exists of `attendance_tracker_<name>/` into `attendance_tracker_<name>_archive.zip`,
3. deletes the incomplete directory,
4. exits with code 130 (Ctrl+C) or 148 (Ctrl+Z).

The trap covers deployment only, not the marking session inside `attendance_checker.py`: it is cleared just before the app starts.

The handler only touches a directory created by the current run. If you interrupt before entering a name, or at the overwrite prompt for an existing project, nothing is zipped or deleted.

**To test it:** start a deploy, enter a project name, and press Ctrl+C (or Ctrl+Z) at the next prompt. Then check:

```bash
ls attendance_tracker_<name>              # gone
unzip -l attendance_tracker_<name>_archive.zip
```

Interrupted at the roster prompt, the zip contains the structure built so far:

```
attendance_tracker_<name>/
attendance_tracker_<name>/attendance_checker.py
attendance_tracker_<name>/Helpers/
attendance_tracker_<name>/Helpers/config.json
attendance_tracker_<name>/reports/
```

## Testing


- Option A with 3 and with all 10 students, and Option B with 4 students: checked the structure, roster rows and `total_sessions`.
- Permissions checked with `ls -l` (`-rwx` on the app, `-rw-------` on `config.json`).
- Threshold update with valid, empty and non-numeric input, then checked `config.json` with `cat` and `python3 -m json.tool`.
- Deploying over an existing directory, answering both overwrite and abort.
- A run with nobody absent, followed by archiving, to check the missing `absent.log` case.
- Invalid input at every prompt (`0`, `15`, `abc`, empty), checking the remaining-attempts message and that the partial directory is removed after the third invalid answer.
- A run with one student present and one absent, then archiving, checking the timestamped filenames and that the archives match the logs.
- Ctrl+C and Ctrl+Z during deployment, before a name was entered, at the overwrite prompt, and during the marking session.
