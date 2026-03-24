#!/usr/bin/env python3
"""
Script to migrate authentication credentials from .env to Doppler
Usage: python migrate-to-doppler.py [--project PROJECT] [--config CONFIG] [--env-file .env]
"""

import os
import re
import sys
import subprocess
import argparse
from typing import Dict, List, Tuple


class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    NC = '\033[0m'  # No Color


def print_color(message: str, color: str):
    """Print colored message"""
    print(f"{color}{message}{Colors.NC}")


def check_doppler_installed() -> bool:
    """Check if Doppler CLI is installed"""
    try:
        subprocess.run(['doppler', '--version'],
                      capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def check_doppler_login() -> bool:
    """Check if user is logged into Doppler"""
    try:
        subprocess.run(['doppler', 'me'],
                      capture_output=True, check=True)
        return True
    except subprocess.CalledProcessError:
        return False


def list_doppler_projects() -> List[str]:
    """List available Doppler projects"""
    try:
        result = subprocess.run(['doppler', 'projects', 'list', '--json'],
                              capture_output=True, check=True, text=True)
        import json
        projects = json.loads(result.stdout)
        return [p['name'] for p in projects]
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []


def project_exists(project: str) -> bool:
    """Check if Doppler project exists"""
    try:
        subprocess.run(['doppler', 'projects', 'get', project],
                      capture_output=True, check=True)
        return True
    except subprocess.CalledProcessError:
        return False


def config_exists(project: str, config: str) -> bool:
    """Check if Doppler config exists"""
    try:
        subprocess.run(['doppler', 'configs', 'get', config,
                       '--project', project],
                      capture_output=True, check=True)
        return True
    except subprocess.CalledProcessError:
        return False


def create_project(project: str, description: str = "Migrated from .env") -> bool:
    """Create Doppler project"""
    try:
        subprocess.run(['doppler', 'projects', 'create', project,
                       '--description', description],
                      check=True)
        return True
    except subprocess.CalledProcessError:
        return False


def create_config(project: str, config: str) -> bool:
    """Create Doppler config"""
    try:
        subprocess.run(['doppler', 'configs', 'create', config,
                       '--project', project],
                      check=True)
        return True
    except subprocess.CalledProcessError:
        return False


def parse_env_file(env_file: str) -> Dict[str, str]:
    """Parse .env file and return dict of key-value pairs"""
    env_vars = {}

    if not os.path.exists(env_file):
        return env_vars

    with open(env_file, 'r') as f:
        for line in f:
            line = line.strip()

            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue

            # Parse key=value
            match = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line)
            if match:
                key = match.group(1)
                value = match.group(2)
                env_vars[key] = value

    return env_vars


def is_auth_variable(key: str) -> bool:
    """Check if variable is authentication-related"""
    auth_patterns = [
        'API_KEY', 'CLIENT_ID', 'CLIENT_SECRET', 'HUBSPOT',
        'PUBLIC_KEY', 'PRIVATE_KEY', 'TOKEN', 'PASSWORD',
        'SECRET', 'CREDENTIALS', 'AUTH'
    ]

    key_upper = key.upper()
    return any(pattern in key_upper for pattern in auth_patterns)


def upload_secret(project: str, config: str, key: str, value: str) -> bool:
    """Upload secret to Doppler"""
    try:
        # Use subprocess to pipe the value to doppler secrets set
        process = subprocess.Popen(
            ['doppler', 'secrets', 'set', key,
             '--project', project, '--config', config, '--silent'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        process.communicate(input=value)
        return process.returncode == 0
    except Exception:
        return False


def migrate_to_doppler(env_file: str, project: str, config: str,
                       dry_run: bool = False) -> Tuple[int, int, int]:
    """
    Migrate authentication variables to Doppler
    Returns: (migrated_count, skipped_count, failed_count)
    """
    env_vars = parse_env_file(env_file)

    migrated = 0
    skipped = 0
    failed = 0

    for key, value in env_vars.items():
        if is_auth_variable(key):
            print_color(f"Migrating: {key}", Colors.YELLOW)

            if dry_run:
                print(f"  Would upload: {key} = {value[:20]}...")
                migrated += 1
            else:
                if upload_secret(project, config, key, value):
                    print_color(f"✓ Successfully migrated: {key}", Colors.GREEN)
                    migrated += 1
                else:
                    print_color(f"✗ Failed to migrate: {key}", Colors.RED)
                    failed += 1
        else:
            print(f"Skipping non-auth variable: {key}")
            skipped += 1

    return migrated, skipped, failed


def main():
    parser = argparse.ArgumentParser(
        description='Migrate authentication credentials from .env to Doppler'
    )
    parser.add_argument('--project', type=str, help='Doppler project name')
    parser.add_argument('--config', type=str, default='dev',
                       help='Doppler config name (default: dev)')
    parser.add_argument('--env-file', type=str, default='.env',
                       help='Path to .env file (default: .env)')
    parser.add_argument('--dry-run', action='store_true',
                       help='Simulate migration without uploading')
    parser.add_argument('--create-project', action='store_true',
                       help='Create project if it doesn\'t exist')

    args = parser.parse_args()

    print_color("=== Doppler Migration Script ===", Colors.YELLOW)
    print()

    # Check Doppler CLI installation
    if not check_doppler_installed():
        print_color("Error: Doppler CLI is not installed", Colors.RED)
        print("Install it with: brew install dopplerhq/cli/doppler")
        sys.exit(1)

    # Check Doppler login
    if not check_doppler_login():
        print_color("You need to login to Doppler first", Colors.YELLOW)
        print("Run: doppler login")
        sys.exit(1)

    # Check .env file
    if not os.path.exists(args.env_file):
        print_color(f"Error: {args.env_file} file not found", Colors.RED)
        sys.exit(1)

    # Handle project selection
    if not args.project:
        print_color("Available Doppler projects:", Colors.YELLOW)
        projects = list_doppler_projects()
        for proj in projects:
            print(f"  - {proj}")
        print()
        print_color("Error: Please specify a project with --project", Colors.RED)
        print("Example: python migrate-to-doppler.py --project my-project --config dev")
        sys.exit(1)

    # Check/create project
    if not project_exists(args.project):
        if args.create_project:
            print_color(f"Creating project '{args.project}'...", Colors.YELLOW)
            if create_project(args.project):
                print_color("Project created successfully", Colors.GREEN)
            else:
                print_color("Failed to create project", Colors.RED)
                sys.exit(1)
        else:
            print_color(f"Project '{args.project}' does not exist", Colors.RED)
            print("Use --create-project flag to create it automatically")
            sys.exit(1)

    # Check/create config
    if not config_exists(args.project, args.config):
        print_color(f"Creating config '{args.config}'...", Colors.YELLOW)
        if create_config(args.project, args.config):
            print_color("Config created successfully", Colors.GREEN)
        else:
            print_color("Failed to create config", Colors.RED)
            sys.exit(1)

    # Perform migration
    print_color(f"Migrating secrets from {args.env_file} to Doppler", Colors.GREEN)
    print(f"Project: {args.project}")
    print(f"Config: {args.config}")
    if args.dry_run:
        print_color("DRY RUN MODE - No changes will be made", Colors.YELLOW)
    print()

    migrated, skipped, failed = migrate_to_doppler(
        args.env_file, args.project, args.config, args.dry_run
    )

    # Print summary
    print()
    print_color("=== Migration Summary ===", Colors.GREEN)
    print(f"Migrated: {migrated}")
    print(f"Skipped: {skipped}")
    print(f"Failed: {failed}")
    print()

    if failed == 0:
        print_color("✓ Migration completed successfully!", Colors.GREEN)
        print()
        print("To use these secrets in your application:")
        print(f"  doppler run --project {args.project} --config {args.config} -- <your-command>")
        print()
        print("Or to view the secrets:")
        print(f"  doppler secrets --project {args.project} --config {args.config}")
    else:
        print_color("Migration completed with errors", Colors.RED)
        sys.exit(1)


if __name__ == '__main__':
    main()
