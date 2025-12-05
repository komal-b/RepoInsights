# Repository Insights Tool

A comprehensive bash script that analyzes GitHub repositories and generates detailed statistics about pull requests, commits, and contributors.

## What It Does

This tool scans your GitHub repository and generates a complete analysis including:

- **Pull Request Statistics**: All PRs with their state, authors, merge info, and timestamps
- **Commit Analysis**: Detailed commit history with file changes, additions, and deletions
- **Author Metrics**: Contributor statistics grouped by GitHub username (deduplicated)
- **Committer Summary**: Alternative grouping by committer name/email
- **Per-User Reports**: Individual CSV files for each contributor's commits
- **Repository Totals**: Aggregate statistics for the entire repo

All results are saved in timestamped folders, preserving the history of each run.

## Prerequisites

Before running the script, you need:

1. **macOS or Linux environment** (designed for macOS compatibility)
2. **Git** - Already installed on most systems
3. **GitHub CLI** (`gh`) - [Installation guide](https://cli.github.com/)
4. **jq** - JSON processor for parsing GitHub API responses
5. **Python 3** - For generating per-user CSV files

### Installing Dependencies

**On macOS** (using Homebrew):
```bash
brew install gh jq python3
```

**On Linux** (Ubuntu/Debian):
```bash
sudo apt-get install gh jq python3
```

## Setup

1. **Authenticate with GitHub CLI**:
```bash
gh auth login
```
Follow the prompts to log in with your GitHub account.

2. **Make the script executable**:
```bash
chmod +x repo_insights.sh
```

## How to Run

### Basic Usage

Navigate to any local Git repository and run:
```bash
./repo_insights.sh
```

This will analyze the entire repository history.

### With Date Filters

You can filter the analysis by date range:

**Analyze commits since a specific date**:
```bash
./repo_insights.sh --since "2024-01-01"
```

**Analyze commits until a specific date**:
```bash
./repo_insights.sh --until "2024-12-31"
```

**Analyze a specific date range**:
```bash
./repo_insights.sh --since "2024-01-01" --until "2024-12-31"
```

### Running from Anywhere (Add to PATH)

To run the script from any directory without specifying the full path, add it to your bash profile:

```bash
echo 'export PATH="$PATH:/path/to/script/directory"' >> ~/.bashrc
source ~/.bashrc
```

Replace `/path/to/script/directory` with the actual directory containing `repo_insights.sh`. After this, you can run:

```bash
cd any-git-repo
repo_insights --since "2024-01-01"
```

**For macOS users**, use `~/.bash_profile` or `~/.zshrc` (if using zsh) instead of `~/.bashrc`.

### Date Format

Dates can be provided in multiple formats:

**Simple date format**:
```bash
./repo_insights.sh --since "2024-01-01"
```

**Date with time** (ISO-8601 format):
```bash
./repo_insights.sh --since "2024-01-01T09:00:00Z" --until "2024-12-31T17:00:00Z"
```

**Relative dates** (Git supports these too):
```bash
./repo_insights.sh --since "2 weeks ago"
./repo_insights.sh --since "last month"
./repo_insights.sh --since "2024-01-01" --until "yesterday"
```

**Common formats**:
- `YYYY-MM-DD` - Simple date (e.g., `2024-01-01`)
- `YYYY-MM-DDTHH:MM:SSZ` - Full ISO-8601 with time (e.g., `2024-01-01T14:30:00Z`)
- `YYYY-MM-DD HH:MM:SS` - Date and time with space (e.g., `2024-01-01 14:30:00`)
- Relative: `"2 weeks ago"`, `"last month"`, `"yesterday"`, etc.

## Output Structure

Each run creates a timestamped folder:

```
repo_insights_output/
├── history_runs.txt              # Log of all runs
└── run_20241204_143022/          # Timestamped folder
    ├── repo_stats.csv            # Overall repository statistics
    ├── prs_all.csv               # All pull requests
    ├── authors_summary.csv       # Contributors grouped by GitHub username
    ├── committers_summary.csv    # Contributors grouped by committer info
    ├── commits_detailed.csv      # Every commit with full details
    └── users/                    # Per-user breakdown
        ├── username1.csv
        ├── username2.csv
        └── ...
```

### Output Files Explained

- **repo_stats.csv**: High-level metrics (total PRs, commits, files changed, lines added/deleted)
- **prs_all.csv**: Complete PR list with state, authors, merge dates, branch names
- **authors_summary.csv**: Each contributor's total commits and line changes (by GitHub username)
- **commits_detailed.csv**: Every commit with SHA, author, date, and diff statistics
- **users/*.csv**: Individual files containing all commits for each user

## Example

```bash
# Clone a repository
git clone https://github.com/owner/repo.git
cd repo

# Run the analysis
../repo_insights.sh --since "2024-01-01"

# View results
open repo_insights_output/run_*/repo_stats.csv
```

## Troubleshooting

**"Run this INSIDE a cloned repo"**
- You must run the script from within a Git repository directory

**"No 'origin' remote found"**
- Ensure your repository has an origin remote: `git remote -v`

**"GitHub CLI not logged in"**
- Run `gh auth login` and complete authentication

**Rate limiting issues**
- The script fetches up to 3,000 PRs and uses GitHub API for each commit
- For very large repositories, you may hit rate limits

## Notes

- The script is designed to be macOS-friendly (no `mapfile` usage)
- GitHub API is used to match commits to GitHub usernames for accurate author deduplication
- All runs are preserved in separate timestamped folders
- The script is safe to run multiple times—it never modifies your repository

## License

Feel free to use and modify this script for your needs.
