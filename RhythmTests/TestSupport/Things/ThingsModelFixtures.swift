import Foundation

@testable import Rhythm

enum ThingsTestFixtures {
  static let sampleTodo = ThingsTodo(
    id: "todo:sample",
    type: .todo,
    title: "Sample",
    status: .incomplete,
    list: "inbox",
    when: nil,
    deadline: nil,
    completedAt: nil,
    createdAt: nil,
    updatedAt: nil,
    notes: nil,
    area: nil,
    project: nil,
    heading: nil,
    tags: [],
    checklistItems: [],
    url: "things:///show?id=sample"
  )

  static let defaultTodo = ThingsTodo(
    id: "todo:todo-id",
    type: .todo,
    title: "Todo",
    status: .incomplete,
    list: "inbox",
    when: nil,
    deadline: nil,
    completedAt: nil,
    createdAt: nil,
    updatedAt: nil,
    notes: nil,
    area: nil,
    project: nil,
    heading: nil,
    tags: [],
    checklistItems: [],
    url: "things:///show?id=todo-id"
  )

  static let defaultProject = ThingsProject(
    id: "project:project-id",
    type: .project,
    title: "Project",
    status: .incomplete,
    list: "anytime",
    when: nil,
    deadline: nil,
    completedAt: nil,
    notes: nil,
    area: nil,
    tags: [],
    createdAt: nil,
    updatedAt: nil,
    headings: [ThingsReference(id: "heading:planning", title: "Planning")],
    todos: nil,
    url: "things:///show?id=project-id"
  )

  static let defaultHeading = ThingsHeading(
    id: "heading:planning",
    type: .heading,
    title: "Planning",
    status: .incomplete,
    isLogged: false,
    completedAt: nil,
    createdAt: nil,
    updatedAt: nil,
    project: ThingsReference(id: "project:project-id", title: "Project"),
    todos: nil,
    url: "things:///show?id=planning"
  )

  static let defaultArea = ThingsArea(
    id: "area:area-id",
    type: .area,
    title: "Work",
    projectCount: 0,
    todoCount: 0,
    projects: nil,
    todos: nil,
    url: "things:///show?id=area-id"
  )

  static let todoWithChecklist = ThingsTodo(
    id: "todo:todo-1",
    type: .todo,
    title: "Prepare launch",
    status: .incomplete,
    list: "anytime",
    when: nil,
    deadline: nil,
    completedAt: nil,
    createdAt: nil,
    updatedAt: nil,
    notes: nil,
    area: nil,
    project: ThingsReference(id: "project:project-1", title: "Launch"),
    heading: nil,
    tags: [],
    checklistItems: [
      ThingsChecklistItem(title: "First", status: .incomplete, id: "row-1", index: 1),
      ThingsChecklistItem(title: "Second", status: .completed, id: "row-2", index: 2),
    ],
    url: "things:///show?id=todo-1"
  )

  static let repeatingMetadata = ThingsRepeatingMetadata(
    isTemplate: true,
    template: nil,
    paused: false,
    nextOccurrence: nil,
    instanceCreationStart: nil,
    instanceCount: nil,
    afterCompletionReferenceAt: nil,
    deadlineOffsetDays: nil,
    ruleDataBase64: nil
  )

  static let heading = ThingsHeading(
    id: "heading:heading-1",
    type: .heading,
    title: "Phase",
    status: .completed,
    isLogged: true,
    completedAt: "2026-07-13T12:00:00Z",
    createdAt: nil,
    updatedAt: nil,
    project: ThingsReference(id: "project:project-1", title: "Launch"),
    todos: [ThingsReference(id: "todo:todo-1", title: "Prepare launch")],
    url: "things:///show?id=heading-1"
  )

  static let projectOne = ThingsProject(
    id: "project:project-1",
    type: .project,
    title: "Launch",
    status: .incomplete,
    list: "anytime",
    when: nil,
    deadline: nil,
    completedAt: nil,
    notes: nil,
    area: nil,
    tags: [],
    createdAt: nil,
    updatedAt: nil,
    headings: [ThingsReference(id: "heading:heading-1", title: "Phase")],
    todos: nil,
    url: "things:///show?id=project-1"
  )

  static let projectTwo = ThingsProject(
    id: "project:project-2",
    type: .project,
    title: "Other",
    status: .incomplete,
    list: "anytime",
    when: nil,
    deadline: nil,
    completedAt: nil,
    notes: nil,
    area: nil,
    tags: [],
    createdAt: nil,
    updatedAt: nil,
    headings: [],
    todos: nil,
    url: "things:///show?id=project-2"
  )

  static let projectInTrash = ThingsProject(
    id: "project:project-in-trash",
    type: .project,
    title: "Deleted Project",
    status: .incomplete,
    list: "trash",
    when: nil,
    deadline: nil,
    completedAt: nil,
    notes: nil,
    area: nil,
    tags: [],
    createdAt: nil,
    updatedAt: nil,
    headings: [],
    todos: nil,
    url: "things:///show?id=project-in-trash"
  )

  static let todoInTrashedProject = ThingsTodo(
    id: "todo:todo-in-trash",
    type: .todo,
    title: "Deleted Child",
    status: .incomplete,
    list: "trash",
    when: nil,
    deadline: nil,
    completedAt: nil,
    createdAt: nil,
    updatedAt: nil,
    notes: nil,
    area: nil,
    project: ThingsReference(id: projectInTrash.id, title: projectInTrash.title),
    heading: nil,
    tags: [],
    checklistItems: [],
    url: "things:///show?id=todo-in-trash"
  )

  static let existingTag = ThingsTag(
    id: "tag:existing",
    type: .tag,
    title: "Existing",
    shortcut: nil,
    todoCount: 0,
    projectCount: 0,
    todos: nil,
    projects: nil,
    url: "things:///show?id=existing"
  )

  static let parentTag = ThingsTag(
    id: "tag:parent",
    type: .tag,
    title: "Parent",
    shortcut: nil,
    todoCount: 0,
    projectCount: 0,
    todos: nil,
    projects: nil,
    url: "things:///show?id=parent"
  )

  static let area = ThingsArea(
    id: "area:area-1",
    type: .area,
    title: "Work",
    projectCount: 0,
    todoCount: 0,
    projects: nil,
    todos: nil,
    url: "things:///show?id=area-1"
  )
}
