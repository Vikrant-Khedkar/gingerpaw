import Foundation
import SwiftUI

public enum JobStatus: String, Sendable, Codable { case planning, ready, running, done, failed }

/// How a job's subtasks execute. `parallel` = independent, each its own worktree off base.
/// `sequential` = cohesive/dependent, each branches off the previous, ending in ONE PR.
public enum JobMode: String, Sendable, Codable { case parallel, sequential }

/// A high-level goal: a planner agent decomposes it into subtasks, the user confirms,
/// then each subtask is dispatched as a normal run (verify + on-green) under the job.
@MainActor
@Observable
final class Job: Identifiable {
    let id = UUID()
    let goal: String
    let repoPath: String
    let verifyCommand: String?
    let mergeMode: MergeMode
    let createdAt: Date

    var status: JobStatus = .planning
    var mode: JobMode = .parallel
    var subtasks: [String] = []
    var plannerRunID: AgentRun.ID?
    var childRunIDs: [AgentRun.ID] = []

    init(goal: String, repoPath: String, verifyCommand: String?, mergeMode: MergeMode, createdAt: Date) {
        self.goal = goal
        self.repoPath = repoPath
        self.verifyCommand = verifyCommand
        self.mergeMode = mergeMode
        self.createdAt = createdAt
    }

    var repoName: String { (repoPath as NSString).lastPathComponent }
}

/// Persisted form of a Job (live `Job`/runs are in-memory; this survives relaunch).
struct JobRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var goal: String
    var repoPath: String
    var status: JobStatus
    var subtasks: [String]
    var childRunIDs: [UUID]
    var createdAt: Date
    var mode: JobMode?
}

struct Plan: Sendable, Equatable {
    var mode: JobMode
    var subtasks: [String]
}

/// Decomposition prompt + tolerant parsing of the planner agent's output.
enum Planner {
    static func prompt(goal: String) -> String {
        """
        You are planning, not coding. Break the following goal into a small set of coding subtasks, \
        and decide how they should run.

        Goal: \(goal)

        Choose a mode:
        - "parallel": the subtasks are INDEPENDENT — they touch different files and don't depend on \
        each other's output. They'll run simultaneously, each in its own branch.
        - "sequential": the subtasks are part of ONE cohesive change — they share files, build on each \
        other, or a later step needs an earlier step's result (e.g. "redesign the page" then \
        "screenshot the redesigned page"). They'll run in order on a shared branch and end in ONE pull request.

        Output ONLY this JSON object, nothing else:
        {"mode": "parallel" | "sequential", "subtasks": ["short task", "short task", ...]}

        Order the subtasks correctly when sequential. Do not write or edit any files. Do not explain.
        """
    }

    /// Parse the planner's `{mode, subtasks}` object; falls back to a bare array (→ parallel)
    /// or bullet lines, so older/looser output still works.
    static func parsePlan(_ text: String) -> Plan {
        if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
           let data = String(text[open...close]).data(using: .utf8) {
            struct Raw: Decodable { var mode: String?; var subtasks: [String]? }
            if let raw = try? JSONDecoder().decode(Raw.self, from: data) {
                let tasks = (raw.subtasks ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !tasks.isEmpty {
                    let mode = JobMode(rawValue: (raw.mode ?? "parallel").lowercased()) ?? .parallel
                    return Plan(mode: mode, subtasks: tasks)
                }
            }
        }
        return Plan(mode: .parallel, subtasks: parse(text))
    }

    /// Pull a `["...","..."]` array out of free-form agent output. Falls back to bullet/numbered
    /// lines if there's no clean JSON array.
    static func parse(_ text: String) -> [String] {
        if let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close {
            let slice = String(text[open...close])
            if let data = slice.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                let cleaned = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !cleaned.isEmpty { return cleaned }
            }
        }
        // Fallback: lines like "- foo", "1. foo", "* foo".
        let bullets = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard let f = s.first else { return nil }
            if f == "-" || f == "*" || f == "•" { s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces) }
            else if f.isNumber { s = s.drop { $0.isNumber }.drop { $0 == "." || $0 == ")" || $0 == " " }.trimmingCharacters(in: .whitespaces) }
            else { return nil }
            return s.isEmpty ? nil : s
        }
        return bullets
    }
}
