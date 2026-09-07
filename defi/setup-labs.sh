#!/usr/bin/env bash
# Makes the Uniswap v4 and Aave v3 test suites runnable.
#
# The protocol repos were cloned shallow, so their lib/ submodules are empty
# stubs and `forge test` cannot run. This fetches the dependencies at versions
# that actually compile these trees, which is fiddlier than it sounds:
#
#   forge-std v1.9.5 is the ONLY version that has both `src/mocks/MockERC20.sol`
#   (removed in v1.9.6) and the newer `Vm.expectEmit` overload (added after
#   v1.9.4). Both trees need both. Do not "upgrade" it.
#
# Usage: ./setup-labs.sh [uni|aave|all]     (default: all)
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"
FS_TAG=v1.9.5

fetch() { # url dest [tag]
  local url=$1 dest=$2 tag=${3:-}
  rmdir "$dest" 2>/dev/null || true
  [ -d "$dest/.git" ] && return 0
  if [ -n "$tag" ]; then git clone -q "$url" "$dest"; ( cd "$dest" && git checkout -q "$tag" )
  else git clone -q --depth 1 "$url" "$dest"; fi
}

forge_std() { # parent_lib_dir
  fetch https://github.com/foundry-rs/forge-std "$1/forge-std" "$FS_TAG"
  fetch https://github.com/dapphub/ds-test "$1/forge-std/lib/ds-test"
}

setup_uni() {
  echo "==> uniswap v4-core"
  cd uni/v4-core
  forge_std lib
  fetch https://github.com/transmissions11/solmate lib/solmate
  fetch https://github.com/openzeppelin/openzeppelin-contracts lib/openzeppelin-contracts
  FOUNDRY_PROFILE=debug forge build
  cd ../..
}

setup_aave() {
  echo "==> aave v3"
  cd aave/aave-v3-origin
  forge_std lib
  fetch https://github.com/aave-dao/solidity-utils lib/solidity-utils
  ( cd lib/solidity-utils && git submodule update --init --recursive -q )
  forge build
  cd ../..
}

case "${1:-all}" in
  uni)  setup_uni ;;
  aave) setup_aave ;;
  all)  setup_uni; setup_aave ;;
  *) echo "usage: $0 [uni|aave|all]"; exit 1 ;;
esac
echo
echo "Done. Try:"
echo "  cd uni/v4-core         && FOUNDRY_PROFILE=debug forge test --match-path test/libraries/Hooks.t.sol"
echo "  cd aave/aave-v3-origin && forge test --match-path tests/protocol/pool/Pool.Supply.t.sol"
