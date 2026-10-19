#!/usr/bin/env node
// Preserve the existing entry point; the browser suite now covers auth, touch,
// circular banners, responsive previews and country-specific contact completion.
import { spawnSync } from 'node:child_process';
const result=spawnSync('python', ['scripts/test_auth_banner_browser.py'], {stdio:'inherit',env:process.env});
if (result.error) throw result.error;
process.exit(result.status ?? 1);
