---
name: ef-core-migrations
description: Create and set up Entity Framework Core migrations the way a service with a dedicated data project does it: a design-time factory, one helper script, timestamp-named migrations applied on startup. Use when asked to add, create, review or remove an EF Core migration, or to set up migrations in a .NET project.
---

# EF Core migrations

The workflow: change the model, run one helper script that wraps `dotnet ef migrations add`, review the generated
code, commit the migration together with the model change. The app applies pending migrations when it starts. The
pieces below are what make that one command work from a clean checkout; check a repo has them before running it.

## What the repo needs

1. **A data project** that holds the `DbContext`, its entity configurations and the `Migrations` folder, with
   `Microsoft.EntityFrameworkCore.Design` referenced (`PrivateAssets=all`) and the provider package (Npgsql, SqlServer,
   ...).
2. **The migrations assembly set explicitly** on the provider options, so migrations land in the data project even when
   the app project is elsewhere:
   ```csharp
   builder.UseNpgsql(connectionString, b => b.MigrationsAssembly(Assembly.GetExecutingAssembly().GetName().Name));
   ```
3. **An `IDesignTimeDbContextFactory<TContext>` in the data project.** This is what lets `dotnet ef` run without a
   startup project, so it never boots the whole app (hosted services, auth, message brokers) just to read the model. It
   builds its own configuration, in this order, with later sources winning:
   ```csharp
   new ConfigurationBuilder()
       .SetBasePath(Directory.GetCurrentDirectory())
       .AddJsonFile("appsettings.json", optional: true)
       .AddJsonFile(Path.Combine("..", "MyApp.Api", "appsettings.json"), optional: true)
       .AddJsonFile("appsettings.Development.json", optional: true)
       .AddJsonFile(Path.Combine("..", "MyApp.Api", "appsettings.Development.json"), optional: true)
       .AddEnvironmentVariables()
       .Build();
   ```
   Then bind the options, give the command a generous timeout (`options.CommandTimeout ??= 180`) and return a context
   built with the same `Configure` method the app uses, so design time and runtime can't drift apart. Because the base
   path is the working directory, the helper script must `cd` into the data project.
4. **Local settings that aren't committed.** The connection string for design time usually lives in a git-ignored
   `appsettings.Development.json` in the data project (and/or the API project). A fresh checkout needs one, or the
   `ConnectionString` environment variable.
5. **Migrations applied at startup**, from a small extension called once during app startup:
   ```csharp
   using var scope = app.ApplicationServices.CreateScope();
   var factory = scope.ServiceProvider.GetRequiredService<IDbContextFactory<AppDbContext>>();
   using var db = factory.CreateDbContext();
   db.Database.Migrate();
   ```
6. **`dotnet-ef` installed**: `dotnet tool install --global dotnet-ef` (or a local tool manifest). Keep it on the same
   major version as the EF packages. A "tools older than the runtime" warning about a patch version is harmless.
7. **The helper script**, checked in as `scripts/add-migration.sh` (or similar): copy [add-migration.sh](add-migration.sh)
   from this skill's directory into the repo, or run it from here. It runs from bash (Git Bash on Windows works).

## Adding a migration

1. Make the model change (entity, configuration class, context) and make sure the data project builds. `dotnet ef`
   needs a restored project, so on a fresh checkout run `dotnet build <data-project>` first.
2. Run the helper from the repo root:
   ```bash
   scripts/add-migration.sh --project src/MyApp.Data --context MyApp.Data.AppDbContext [name]
   ```
   - With no name it is called `<context>.<yyyy_MM_dd_HH_mm_ss>` (for example `appdbcontext.2026_10_28_12_39_47`).
     Timestamp names never collide between branches and sort in creation order. Pass a name only when the repo's
     convention is descriptive names.
   - Design time runs as `Development`, so the Development settings supply the connection string.
   - `--startup <dir>` is only for a context that has no design-time factory; `--output` changes the folder;
     `--verbose` passes `-v` to `dotnet ef` when something fails opaquely.
   - Adding a migration does not touch the database: it compares the model with the snapshot file.
3. **Review the generated files before committing.** Three files appear or change: `<timestamp>_<name>.cs`,
   `<timestamp>_<name>.Designer.cs` and `<Context>ModelSnapshot.cs`. Commit all three together, with the model change.
   Read `Up` and `Down`:
   - An empty `Up` means the model didn't change; remove the migration (below) and find out why.
   - Unexpected changes (renamed columns, dropped-and-recreated constraints, lots of unrelated tables) usually mean the
     snapshot was stale or a naming convention changed. Don't commit noise; sort out the cause first.
   - Anything destructive (`DropColumn`, `DropTable`, `AlterColumn` that narrows or converts a type) loses data on a
     real database. EF will not preserve it for you: a rename generated as drop-and-add, or a type conversion without
     a `USING` clause, needs the migration edited by hand (`RenameColumn`, `migrationBuilder.Sql(...)`). Tell the user
     what the migration does to existing rows.
4. Run the build and tests. If the migration was only generated and the DB is a shared or real one, **don't apply it
   yourself** (see below).

## Undoing and fixing

- Not yet applied or committed: `dotnet ef migrations remove -c <context>` run in the data project (same working
  directory and environment as the script) deletes the latest migration and reverts the snapshot. Never delete the
  files by hand; the snapshot would go out of step.
- Already applied anywhere (committed and deployed, or run against someone's database): never edit or remove it. Add a
  new migration that fixes it forward.
- Merge conflicts in the snapshot or two branches each adding a migration: take the other branch's snapshot, remove
  your migration (`migrations remove`), then re-add it so it is built on top of theirs. Don't hand-merge a snapshot.

## Applying

The app applies pending migrations at startup, so there is normally nothing to run. That also means **starting the app
migrates whatever database its connection string points to**. Check which database that is before running it, and
before `dotnet ef database update`, which does the same thing explicitly. The Development connection string may point
at a shared server. If so, confirm with the user rather than applying to it, or point `ConnectionString` at a local
throwaway database.

Migrations that must run fast against big tables, or need to be applied by a separate pipeline step, can be rendered
with `dotnet ef migrations script <from> <to> -c <context> -o out.sql --idempotent` instead of relying on startup.
