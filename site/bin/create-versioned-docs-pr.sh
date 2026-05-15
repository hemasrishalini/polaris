#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

set -e

cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <release-version>"
  exit 1
fi

VERSION="$1"

BRANCH_NAME="versioned-docs-${VERSION}"

echo "Using branch ${BRANCH_NAME}"

echo "Preparing versioned docs PR for release ${VERSION}"

if [[ ! -d content/releases ]]; then
  echo "content/releases worktree is missing"
  echo "Run site/bin/checkout-releases.sh first"
  exit 1
fi


RELEASE_DIR="content/releases/${VERSION}"

echo "Release directory: ${RELEASE_DIR}"

if [[ -d "${RELEASE_DIR}" ]]; then
  echo "Release directory already exists: ${RELEASE_DIR}"
  exit 1
fi

mkdir -p "${RELEASE_DIR}"

echo "Created release directory"

cp -r content/in-dev/unreleased/* "${RELEASE_DIR}/"

echo "Copied unreleased documentation"

LATEST_INDEX="content/releases/latest/index.md"

sed -i "s|redirect_to: '/releases/.*/'|redirect_to: '/releases/${VERSION}/'|" "${LATEST_INDEX}"

echo "Updated latest release redirect"