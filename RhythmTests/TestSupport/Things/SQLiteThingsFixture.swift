import Foundation
import SQLite3

@testable import Rhythm

@MainActor
final class SQLiteThingsFixture: ThingsDatabaseAccessing {
  private let databaseURL: URL

  init() throws {
    databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("things-mcp-\(UUID().uuidString).sqlite")

    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
      throw SQLiteFixtureError.open
    }
    defer { sqlite3_close(database) }

    try Self.execute(
      """
      CREATE TABLE TMTask (
          uuid TEXT PRIMARY KEY,
          title TEXT,
          type INTEGER NOT NULL,
          status INTEGER NOT NULL DEFAULT 0,
          trashed INTEGER NOT NULL DEFAULT 0,
          rt1_recurrenceRule BLOB,
          rt1_repeatingTemplate TEXT,
          rt1_instanceCreationStartDate INTEGER,
          rt1_instanceCreationPaused INTEGER,
          rt1_instanceCreationCount INTEGER,
          rt1_afterCompletionReferenceDate REAL,
          rt1_nextInstanceStartDate INTEGER,
          t2_deadlineOffset INTEGER,
          start INTEGER DEFAULT 0,
          startDate INTEGER,
          startBucket INTEGER DEFAULT 0,
          reminderTime INTEGER,
          deadline INTEGER,
          deadlineSuppressionDate INTEGER,
          stopDate REAL,
          creationDate REAL,
          userModificationDate REAL,
          notes TEXT,
          area TEXT,
          project TEXT,
          heading TEXT,
          todayIndex INTEGER DEFAULT 0,
          "index" INTEGER DEFAULT 0
      );
      CREATE TABLE TMArea (
          uuid TEXT PRIMARY KEY,
          title TEXT,
          visible INTEGER,
          "index" INTEGER DEFAULT 0
      );
      CREATE TABLE TMTag (
          uuid TEXT PRIMARY KEY,
          title TEXT,
          shortcut TEXT,
          parent TEXT,
          trashed INTEGER DEFAULT 0,
          "index" INTEGER DEFAULT 0
      );
      CREATE TABLE TMTaskTag (tasks TEXT, tags TEXT);
      CREATE TABLE TMAreaTag (areas TEXT, tags TEXT);
      CREATE TABLE TMChecklistItem (
          uuid TEXT,
          task TEXT,
          title TEXT,
          status INTEGER DEFAULT 0,
          stopDate REAL,
          creationDate REAL,
          userModificationDate REAL,
          leavesTombstone INTEGER DEFAULT 0,
          "index" INTEGER DEFAULT 0
      );
      CREATE TABLE TMSettings (uuid TEXT PRIMARY KEY, uriSchemeAuthenticationToken TEXT);

      INSERT INTO TMArea (uuid, title, visible, "index")
      VALUES ('area-12345678901234567890', 'Team''s Area', 1, 1);
      INSERT INTO TMTag (uuid, title, shortcut, trashed, "index")
      VALUES ('tag-12345678901234567890', 'Deep Work', 'd', 0, 1);
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, creationDate,
          userModificationDate, notes, area, "index"
      ) VALUES (
          'project-12345678901234567890', 'Client''s Launch', 1, 0, 0, 1,
          100, 300, 'Project notes', 'area-12345678901234567890', 1
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, creationDate,
          userModificationDate, project, "index"
      ) VALUES (
          'heading-12345678901234567890', 'Launch''s Phase', 2, 0, 0, 1,
          110, 290, 'project-12345678901234567890', 1
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, creationDate,
          userModificationDate, notes, heading, "index"
      ) VALUES (
          'todo-12345678901234567890', 'O''Brien''s plan', 0, 0, 0, 0,
          120, 200, 'Quoted notes', 'heading-12345678901234567890', 1
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, stopDate, creationDate,
          userModificationDate, notes, project, "index"
      ) VALUES (
          'todo-22345678901234567890', 'Archived O''Brien task', 0, 3, 0, 1,
          220, 130, 250, 'Completed notes', 'project-12345678901234567890', 2
      );
      INSERT INTO TMTaskTag (tasks, tags)
      VALUES ('todo-12345678901234567890', 'tag-12345678901234567890');
      INSERT INTO TMTaskTag (tasks, tags)
      VALUES ('project-12345678901234567890', 'tag-12345678901234567890');
      INSERT INTO TMChecklistItem (uuid, task, title, status, leavesTombstone, "index")
      VALUES (
          'checklist-12345678901234567890',
          'todo-12345678901234567890',
          'Review PR',
          0,
          0,
          1
      );

      INSERT INTO TMArea (uuid, title, visible, "index")
      VALUES ('area-22345678901234567890', 'Research Area', 1, 2);
      INSERT INTO TMTag (uuid, title, shortcut, parent, trashed, "index")
      VALUES ('tag-parent-12345678901234567890', 'Work', NULL, NULL, 0, 2);
      INSERT INTO TMTag (uuid, title, shortcut, parent, trashed, "index")
      VALUES (
          'tag-child-12345678901234567890',
          'Deep Focus',
          'f',
          'tag-parent-12345678901234567890',
          0,
          3
      );
      INSERT INTO TMAreaTag (areas, tags)
      VALUES ('area-22345678901234567890', 'tag-child-12345678901234567890');

      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, creationDate,
          userModificationDate, notes, area, "index"
      ) VALUES (
          'project-32345678901234567890', 'Advanced Reads', 1, 0, 0, 1,
          1783936800, 1784026800, 'Advanced project',
          'area-22345678901234567890', 3
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, startDate, startBucket,
          reminderTime, creationDate, userModificationDate, notes, project, "index"
      ) VALUES (
          'todo-32345678901234567890', 'Inherited context', 0, 0, 0, 2,
          132806272, 1, 1255145472, 1783936800, 1784026800,
          'The title is intentionally unrelated',
          'project-32345678901234567890', 1
      );
      INSERT INTO TMChecklistItem (
          uuid, task, title, status, creationDate, userModificationDate,
          leavesTombstone, "index"
      ) VALUES (
          'checklist-22345678901234567890',
          'todo-32345678901234567890',
          'Hidden needle alpha',
          0,
          1783936800,
          1784026800,
          0,
          1
      );
      INSERT INTO TMChecklistItem (
          uuid, task, title, status, creationDate, userModificationDate,
          leavesTombstone, "index"
      ) VALUES (
          'checklist-32345678901234567890',
          'todo-32345678901234567890',
          'Hidden needle beta',
          0,
          1783936800,
          1784026800,
          0,
          2
      );

      INSERT INTO TMTask (
          uuid, title, type, status, trashed, rt1_recurrenceRule,
          rt1_instanceCreationStartDate, rt1_instanceCreationPaused,
          rt1_instanceCreationCount, rt1_afterCompletionReferenceDate,
          rt1_nextInstanceStartDate, t2_deadlineOffset, start, project, "index"
      ) VALUES (
          'todo-repeat-12345678901234567890', 'Weekly review template', 0, 0, 0,
          X'01020304', 132806272, 1, 4, 1784116800, 132807168, -2, 2,
          'project-32345678901234567890', 2
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, rt1_repeatingTemplate,
          start, startDate, project, "index"
      ) VALUES (
          'todo-instance-12345678901234567890', 'Weekly review instance', 0, 0, 0,
          'todo-repeat-12345678901234567890', 2, 132806272,
          'project-32345678901234567890', 3
      );

      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, stopDate, creationDate,
          userModificationDate, "index"
      ) VALUES (
          'project-dated-12345678901234567890', 'Dated project', 1, 3, 0, 1,
          1784116800, 1783936800, 1784026800, 4
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, stopDate, creationDate,
          userModificationDate, "index"
      ) VALUES (
          'todo-dated-12345678901234567890', 'Dated completion', 0, 3, 0, 1,
          1784116800, 1783936800, 1784026800, 4
      );
      INSERT INTO TMTaskTag (tasks, tags) VALUES
          ('project-dated-12345678901234567890', 'tag-child-12345678901234567890'),
          ('todo-dated-12345678901234567890', 'tag-child-12345678901234567890');

      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, stopDate, creationDate,
          userModificationDate, "index"
      ) VALUES (
          'project-logged-12345678901234567890', 'Logged parent project', 1, 3, 0,
          1, 1784116800, 1783936800, 1784026800, 5
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, creationDate,
          userModificationDate, project, "index"
      ) VALUES (
          'heading-logged-12345678901234567890', 'Archived section', 2, 0, 0, 1,
          1783936800, 1784026800, 'project-logged-12345678901234567890', 1
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, creationDate,
          userModificationDate, heading, "index"
      ) VALUES (
          'todo-logged-12345678901234567890', 'Reopened logged child', 0, 0, 0, 1,
          1783936800, 1784026800, 'heading-logged-12345678901234567890', 1
      );

      INSERT INTO TMTask (uuid, title, type, status, trashed, start, "index")
      VALUES (
          'todo-trash-12345678901234567890', 'Trash needle', 0, 0, 1, 1, 6
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, project, "index"
      ) VALUES (
          'heading-trash-12345678901234567890', 'Trashed heading needle', 2, 0, 1,
          1, 'project-32345678901234567890', 6
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, heading, "index"
      ) VALUES (
          'todo-heading-trash-12345678901234567890',
          'Heading inherited deletion',
          0,
          0,
          0,
          1,
          'heading-trash-12345678901234567890',
          7
      );
      INSERT INTO TMTask (uuid, title, type, status, trashed, start, "index")
      VALUES (
          'project-trash-12345678901234567890',
          'Trashed parent project',
          1,
          0,
          1,
          1,
          7
      );
      INSERT INTO TMTask (
          uuid, title, type, status, trashed, start, project, "index"
      ) VALUES (
          'todo-project-trash-12345678901234567890',
          'Project inherited deletion',
          0,
          0,
          0,
          1,
          'project-trash-12345678901234567890',
          8
      );
      INSERT INTO TMSettings (uuid, uriSchemeAuthenticationToken)
      VALUES ('RhAzEf6qDxCD5PmnZVtBZR', 'fixture-token');
      """,
      in: database
    )
  }

  func withReadableDatabaseURL<T>(_ operation: (URL) throws -> T) throws -> T {
    try operation(databaseURL)
  }

  func remove() {
    try? FileManager.default.removeItem(at: databaseURL)
  }

  private static func execute(_ sql: String, in database: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    guard result == SQLITE_OK else {
      let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
      sqlite3_free(errorMessage)
      throw SQLiteFixtureError.execute(message)
    }
  }
}

enum SQLiteFixtureError: Error {
  case open
  case execute(String)
}
