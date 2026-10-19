import Foundation
import StudyCore

/// Documented WaniKani response shapes. Assignment level deliberately does not exist.
public enum DownloadFixture {
  public static let date = "2026-10-17T00:00:00.000000Z"
  public static func resource(_ id: Int, _ object: String, _ data: [String: Any]) -> [String: Any] {
    ["id": id, "object": object, "data": data]
  }
  public static func collection(_ rows: [[String: Any]], next: String? = nil, total: Int? = nil)
    -> [String: Any]
  {
    [
      "object": "collection", "total_count": total ?? rows.count,
      "pages": ["next_url": next.map { $0 as Any } ?? NSNull()], "data": rows,
    ]
  }
  public static var user: [String: Any] {
    [
      "object": "user",
      "data": [
        "id": "fixture-user-id", "username": "test", "level": 12,
        "profile_url": "https://www.wanikani.com/users/test", "started_at": date,
        "current_vacation_started_at": NSNull(),
        "subscription": ["active": true, "max_level_granted": 60, "period_ends_at": NSNull()],
      ],
    ]
  }
  public static func subject(_ id: Int, kind: String = "kanji", hidden: Bool = false) -> [String:
    Any]
  {
    var data: [String: Any] = [
      "characters": id == 1 ? "一" : "はい", "level": 1,
      "slug": "fixture", "document_url": "https://www.wanikani.com/kanji/一",
      "hidden_at": hidden ? date as Any : NSNull(),
      "lesson_position": id, "spaced_repetition_system_id": 1,
      "meaning_mnemonic": "A <kanji>fixture</kanji> mnemonic.",
      "meaning_hint": "Meaning hint", "reading_mnemonic": "Reading mnemonic",
      "reading_hint": "Reading hint",
      "meanings": [
        ["meaning": "One", "primary": true, "accepted_answer": true],
        ["meaning": "Single", "primary": false, "accepted_answer": true],
      ],
      "auxiliary_meanings": [
        ["meaning": "Only", "type": "whitelist"], ["meaning": "Wrong", "type": "blacklist"],
      ],
      "readings": [
        ["reading": "いち", "primary": true, "accepted_answer": true, "type": "onyomi"],
        ["reading": "ひと", "primary": false, "accepted_answer": false, "type": "kunyomi"],
      ],
      "component_subject_ids": [3], "amalgamation_subject_ids": [5],
      "visually_similar_subject_ids": [4],
    ]
    if kind == "radical" {
      data["characters"] = NSNull()
      data["readings"] = nil
      data["character_images"] = [
        [
          "url": "https://cdn.wanikani.com/fixture.svg", "content_type": "image/svg+xml",
          "metadata": ["inline_styles": true],
        ]
      ]
    }
    if kind == "kana_vocabulary" {
      data["readings"] = nil
      data["component_subject_ids"] = nil
    }
    if kind == "vocabulary" || kind == "kana_vocabulary" {
      data["context_sentences"] = [["ja": "はい。", "en": "Yes."]]
      data["parts_of_speech"] = ["noun", "の adjective", "future_kind"]
      data["pronunciation_audios"] = [
        [
          "url": "https://cdn.wanikani.com/fixture.mp3", "content_type": "audio/mpeg",
          "metadata": ["voice_actor_id": 1],
        ]
      ]
    }
    return resource(id, kind, data)
  }
  public static var assignment: [String: Any] {
    resource(
      101, "assignment",
      [
        "subject_id": 1, "subject_type": "kanji", "srs_stage": 5,
        "available_at": date, "unlocked_at": date, "started_at": date, "hidden": false,
      ])
  }
  public static var rows: [String: [[String: Any]]] {
    [
      "subjects": [
        subject(1), subject(2, kind: "kana_vocabulary"), subject(3, kind: "radical"),
        subject(4, hidden: true), subject(5, kind: "vocabulary"),
      ],
      "assignments": [assignment],
      "study_materials": [
        resource(
          201, "study_material",
          [
            "subject_id": 1, "meaning_note": "Local study", "reading_note": "いち",
            "meaning_synonyms": ["Single"],
          ])
      ],
      "review_statistics": [
        resource(
          301, "review_statistic",
          [
            "subject_id": 1, "subject_type": "kanji", "created_at": date,
            "meaning_correct": 8, "meaning_incorrect": 2, "meaning_current_streak": 3,
            "meaning_max_streak": 5,
            "reading_correct": 6, "reading_incorrect": 4, "reading_current_streak": 2,
            "reading_max_streak": 4,
            "percentage_correct": 70, "hidden": false,
          ])
      ],
      "level_progressions": [
        resource(
          401, "level_progression",
          [
            "level": 1, "created_at": date, "unlocked_at": date,
            "started_at": date, "passed_at": date, "completed_at": date, "abandoned_at": NSNull(),
          ])
      ],
      "spaced_repetition_systems": [
        resource(
          1, "spaced_repetition_system",
          [
            "name": "Synthetic review system", "unlocking_stage_position": 0,
            "starting_stage_position": 1, "passing_stage_position": 5, "burning_stage_position": 9,
            "stages": (0...9).map { position in
              [
                "position": position,
                "interval": position == 0 || position == 9 ? NSNull() : 10 as Any,
                "interval_unit": position == 0 || position == 9 ? NSNull() : "hours" as Any,
              ]
            },
          ])
      ],
      "voice_actors":
        [
          resource(
            1, "voice_actor",
            ["name": "Fixture", "gender": "female", "description": "Tokyo accent"])
        ],
    ]
  }
  public static func response(_ request: URLRequest, object: [String: Any], status: Int = 200)
    throws -> (Data, HTTPURLResponse)
  {
    (
      try JSONSerialization.data(withJSONObject: object),
      HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    )
  }
  public static func response(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
    let path = request.url!.lastPathComponent
    return try response(request, object: path == "user" ? user : collection(rows[path] ?? []))
  }
}
