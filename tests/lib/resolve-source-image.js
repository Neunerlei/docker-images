#!/usr/bin/env node
/**
 * resolve-source-image.js — CI helper for the test workflows.
 *
 * Resolves the EXACT source-image tag (e.g. "library/python:3.13.8-slim-trixie")
 * for a possibly partial tracked version ("3.13") by calling the release
 * tooling itself (.github/.release/util/docker-version-utils.js) — the same
 * getAllTags / parseVersionTags / resolvePartialVersion / buildTagFilterByArgs
 * chain the publish pipeline uses. Version logic deliberately lives ONLY in
 * the release tooling; this script contains none of it.
 *
 * Usage:
 *   node tests/lib/resolve-source-image.js <namespace> <name> <type> <os> <version> [precision]
 *
 * Prints "<namespace>/<name>:<exact-tag>" on stdout; exits 1 with a readable
 * error when the version cannot be resolved among the registry tags.
 *
 * Requires the release tooling's node modules (npm ci in .github/.release —
 * the same setup the publish workflows use).
 */
const {getAllTags, parseVersionTags, resolvePartialVersion, buildTagFilterByArgs, buildImageNameByArgs} = require('../../.github/.release/util/docker-version-utils');

(async () => {
    const [namespace, name, type, os, version, precisionArg] = process.argv.slice(2);

    for (const [arg, value] of [['namespace', namespace], ['name', name], ['version', version]]) {
        if (!value) {
            console.error(`Missing required argument: ${arg}`);
            console.error('Usage: resolve-source-image.js <namespace> <name> <type> <os> <version> [precision]');
            process.exit(1);
        }
    }

    const precision = parseInt(precisionArg || '3', 10);
    const sourceImage = buildImageNameByArgs({namespace, name});
    const filter = buildTagFilterByArgs({type, os});

    const allTags = await getAllTags(sourceImage);
    const versions = parseVersionTags(allTags, precision, filter);

    const resolved = resolvePartialVersion(versions, version);
    if (!resolved) {
        console.error(`Source version "${version}" not found among the ${versions.size} versioned tags of ${sourceImage} (filter: "${filter || 'none'}").`);
        process.exit(1);
    }
    // Informational only — stdout carries exactly one line: the resolved tag
    if (resolved !== version) {
        console.error(`Resolved "${version}" to "${resolved}"`);
    }

    console.log(`${sourceImage}:${versions.get(resolved)}`);
})();
