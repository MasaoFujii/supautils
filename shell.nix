with import (builtins.fetchTarball {
  name = "2022-10-14";
  url = "https://github.com/NixOS/nixpkgs/archive/cc090d2b942f76fad83faf6e9c5ed44b73ba7114.tar.gz";
  sha256 = "0a1wwpbn2f38pcays6acq1gz19vw4jadl8yd3i3cd961f1x2vdq2";
}) {};
let
  supautils = { postgresql }:
    stdenv.mkDerivation {
      name = "supautils";
      buildInputs = [ postgresql ];
      src = ./.;
      installPhase = ''
        mkdir -p $out/bin
        install -D supautils.so -t $out/lib

        # Build stdlib
        ./bin/build_stdlib.sh

        install -D -t $out/share/postgresql/extension sql/supautils--*.sql
        install -D -t $out/share/postgresql/extension supautils.control
      '';
    };
  pgWithExt = { postgresql } :
    let pg = postgresql.withPackages (p: [ (supautils {inherit postgresql;}) ]);
    in ''
      export PATH=${pg}/bin:"$PATH"

      tmpdir="$(mktemp -d)"

      export PGDATA="$tmpdir"
      export PGHOST="$tmpdir"
      export PGUSER=postgres
      export PGDATABASE=postgres

      trap 'pg_ctl stop -m i && rm -rf "$tmpdir"' sigint sigterm exit

      PGTZ=UTC initdb --no-locale --encoding=UTF8 --nosync -U "$PGUSER"

      options="-F -c listen_addresses=\"\" -k $PGDATA -c shared_preload_libraries=\"supautils\""

      reserved_roles="supabase_storage_admin, anon, reserved_but_not_yet_created"
      reserved_memberships="pg_read_server_files, pg_write_server_files, pg_execute_server_program, role_with_reserved_membership"
      privileged_extensions="hstore"
      privileged_extensions_custom_scripts_path="$tmpdir/privileged_extensions_custom_scripts"

      reserved_stuff_options="-c supautils.reserved_roles=\"$reserved_roles\" -c supautils.reserved_memberships=\"$reserved_memberships\" -c supautils.privileged_extensions=\"$privileged_extensions\" -c supautils.privileged_extensions_custom_scripts_path=\"$privileged_extensions_custom_scripts_path\""
      placeholder_stuff_options='-c supautils.placeholders="response.headers, another.placeholder" -c supautils.placeholders_disallowed_values="\"content-type\",\"x-special-header\",special-value"'

      pg_ctl start -o "$options" -o "$reserved_stuff_options" -o "$placeholder_stuff_options"

      mkdir -p "$tmpdir/privileged_extensions_custom_scripts/hstore"
      echo 'create table t1();' > "$tmpdir/privileged_extensions_custom_scripts/hstore/before-create.sql"
      echo 'drop table t1; create table t2 as values (1);' > "$tmpdir/privileged_extensions_custom_scripts/hstore/after-create.sql"

      createdb contrib_regression

      psql -v ON_ERROR_STOP=1 -f test/fixtures.sql -d contrib_regression

      "$@"
    '';
  supautils-with-pg-12 = writeShellScriptBin "supautils-with-pg-12" (pgWithExt { postgresql = postgresql_12; });
  supautils-with-pg-13 = writeShellScriptBin "supautils-with-pg-13" (pgWithExt { postgresql = postgresql_13; });
  supautils-with-pg-14 = writeShellScriptBin "supautils-with-pg-14" (pgWithExt { postgresql = postgresql_14; });
  supautils-with-pg-15 = writeShellScriptBin "supautils-with-pg-15" (pgWithExt { postgresql = postgresql_15; });
in
mkShell {
  buildInputs = [ supautils-with-pg-12 supautils-with-pg-13 supautils-with-pg-14 supautils-with-pg-15];
}
