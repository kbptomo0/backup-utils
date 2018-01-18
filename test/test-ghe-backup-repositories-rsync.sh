#!/usr/bin/env bash
# ghe-backup-repositories-rsync command tests

# Bring in testlib
# shellcheck source=test/testlib.sh
. "$(dirname "$0")/testlib.sh"

# Create the backup data dir and fake remote repositories dirs
mkdir -p "$GHE_DATA_DIR" "$GHE_REMOTE_DATA_USER_DIR/repositories"
mkdir -p "$TRASHDIR/hooks"

# Run under the remote repositories directory
cd "$GHE_REMOTE_DATA_USER_DIR/repositories"

# Create some test repositories in the remote repositories dir
repo1="0/nw/01/aa/3f/1234/1234.git"
repo2="0/nw/01/aa/3f/1234/1235.git"
repo3="1/nw/23/bb/4c/2345/2345.git"
mkdir -p "$repo1" "$repo2" "$repo3"

wiki1="0/nw/01/aa/3f/1234/1234.wiki.git"
mkdir -p "$wiki1"

gist1="0/01/aa/3f/gist/93069ad4c391b6203f183e147d52a97a.git"
gist2="1/23/bb/4c/gist/1234.git"
mkdir -p "$gist1" "$gist2"

# Initialize test repositories with a fake commit
while IFS= read -r -d '' repo; do
  git init -q --bare "$repo"
  git --git-dir="$repo" --work-tree=. commit -q --allow-empty -m 'test commit'
  rm -rf "$repo/hooks"
  ln -s "$TRASHDIR/hooks" "$repo/hooks"
done <   <(find . -type d -name '*.git' -prune -print0)

# Generate a packed-refs file in repo1
git --git-dir="$repo1" pack-refs

# Generate a pack in repo2
git --git-dir="$repo2" repack -q

# Add some fake svn data to repo3
echo "fake svn history data" > "$repo3/svn.history.msgpack"
mkdir "$repo3/svn_data"
echo "fake property history data" > "$repo3/svn_data/property_history.msgpack"

begin_test "ghe-backup-repositories-rsync first snapshot"
(
    set -e

    # force snapshot number instead of generating a timestamp
    GHE_SNAPSHOT_TIMESTAMP=1
    export GHE_SNAPSHOT_TIMESTAMP

    # run it
    ghe-backup-repositories-rsync

    # check that repositories directory was created
    [ -d "$GHE_DATA_DIR/1/repositories" ]

    # check that packed-refs file was transferred
    [ -f "$GHE_DATA_DIR/1/repositories/$repo1/packed-refs" ]

    # check that a pack file was transferred
    for packfile in $GHE_DATA_DIR/1/repositories/$repo2/objects/pack/*.pack; do
      [ -f "$packfile" ]
    done

    # check that svn data was transferred
    [ -f "$GHE_DATA_DIR"/1/repositories/$repo3/svn.history.msgpack ]
    [ -f "$GHE_DATA_DIR"/1/repositories/$repo3/svn_data/property_history.msgpack ]

    # verify all repository data was transferred
    diff -ru "$GHE_REMOTE_DATA_USER_DIR/repositories" "$GHE_DATA_DIR/1/repositories"
)
end_test


begin_test "ghe-backup-repositories-rsync subsequent snapshot"
(
    set -e

    # force snapshot number instead of generating a timestamp
    GHE_SNAPSHOT_TIMESTAMP=2
    export GHE_SNAPSHOT_TIMESTAMP

    # make current symlink point to previous increment
    ln -s 1 "$GHE_DATA_DIR/current"

    # run it
    ghe-backup-repositories-rsync

    # check that repositories directory was created
    snapshot="$GHE_DATA_DIR/2/repositories"
    [ -d "$snapshot" ]

    # verify hard links used for existing files
    inode1=$(ls -i "$GHE_DATA_DIR/1/repositories/$repo1/packed-refs" | awk '{ print $1; }')
    inode2=$(ls -i "$GHE_DATA_DIR/2/repositories/$repo1/packed-refs" | awk '{ print $1; }')
    [ "$inode1" = "$inode2" ]

    # verify all repository data exists in the increment
    diff -ru "$GHE_REMOTE_DATA_USER_DIR/repositories" "$GHE_DATA_DIR/2/repositories"
)
end_test


begin_test "ghe-backup-repositories-rsync __special__ dirs"
(
    set -e

    # force snapshot number instead of generating a timestamp
    GHE_SNAPSHOT_TIMESTAMP=3
    export GHE_SNAPSHOT_TIMESTAMP

    # create the included __purgatory__ dir on the remote side
    mkdir -p "$GHE_REMOTE_DATA_USER_DIR/repositories/__purgatory__/123.git"
    git init --bare -q "$GHE_REMOTE_DATA_USER_DIR/repositories/__purgatory__/123.git"
    git --git-dir="$GHE_REMOTE_DATA_USER_DIR/repositories/__purgatory__/123.git" --work-tree=. \
        commit --allow-empty -m 'test commit'

    # run it
    ghe-backup-repositories-rsync

    # check that repositories directory was created
    snapshot="$GHE_DATA_DIR/3/repositories"
    [ -d "$snapshot" ]

    # check that included special dir was not transferred
    [ -d "$snapshot/__purgatory__" ]

    # check that all files were transferred under included dir
    [ -f "$snapshot/__purgatory__/123.git/description" ]

    # fsck the repo to make sure everything was transferred
    git --git-dir="$snapshot/__purgatory__/123.git" fsck
)
end_test

begin_test "ghe-backup-repositories-rsync temp files"
(
    set -e

    # force snapshot number instead of generating a timestamp
    GHE_SNAPSHOT_TIMESTAMP=4
    export GHE_SNAPSHOT_TIMESTAMP

    # create a tmp pack to emulate a pack being written to
    touch "$GHE_REMOTE_DATA_USER_DIR/repositories/$repo1/objects/pack/tmp_pack_1234"

    # run it
    ghe-backup-repositories-rsync

    # check that repositories directory was created
    snapshot="$GHE_DATA_DIR/4/repositories"
    [ -d "$snapshot" ]

    # check that tmp pack was not transferred
    [ ! -d "$snapshot/$repo1/objects/pack/tmp_pack_1234" ]
)
end_test
