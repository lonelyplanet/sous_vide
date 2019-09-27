Feature: Event processing
  chef-client will emit events in the following order:

    1. resource_action_start
    2. resource_* events (possibly multiple)
    3. resource_action_complete

  Examples defined here execute various flows and then we verify state of
  the handler and relevant properties of the processed resource.

  Background:
    Given I reset SousVide state
    And Chef why-run mode is disabled
    And I have a chef resource "execute[/bin/true]" with action "install"
    And the "run_phase" is "converge"

  Scenario: resource processing - updated
    When I call "resource_action_start"
    When I call "resource_updated"
    When I call "resource_completed"
    Then current resource "status" should be "updated"
    And  current resource "execution_phase" should be "converge"
    And "resource_collection_cursor" should be "1"
    And there is "1" resources processed in total

  Scenario: resource processing - up-to-date
    When I call "resource_action_start"
    And I call "resource_up_to_date"
    And I call "resource_completed"
    Then current resource "status" should be "up-to-date"
    And "resource_collection_cursor" should be "1"
    And there is "1" resources processed in total

  Scenario: resource processing - skipped
    And this chef resource has a guard "not_if '/bin/false'"
    When I call "resource_action_start"
    And I call "resource_skipped"
    And I call "resource_completed"
    Then current resource "status" should be "skipped"
    And "resource_collection_cursor" should be "1"
    And current resource "guard_description" should be "not_if '/bin/false'"
    And there is "1" resources processed in total

  Scenario: resource processing - why-run
    Given Chef why-run mode is enabled
    When I call "resource_action_start"
    And I call "resource_completed"
    Then "resource_collection_cursor" should be "0"
    And there is "1" resources processed in total
    And current resource "status" should be "why-run"

  Scenario: resource processing - failed
    When I call "resource_action_start"
    And I call "resource_failed"
    And I call "resource_completed"
    Then "resource_collection_cursor" should be "1"
    And there is "1" resources processed in total
    And current resource "status" should be "failed"
    And current resource "retries" should be "0"
    And current resource "error_source" should be "execute '/bin/true'"

  Scenario: resource processing - failed retriable
    When I call "resource_action_start"
    And I call "resource_failed_retriable"
    And I call "resource_up_to_date"
    And I call "resource_completed"
    Then "resource_collection_cursor" should be "1"
    And there is "1" resources processed in total
    And current resource "status" should be "up-to-date"
    And current resource "retries" should be "1"
    And current resource "error_source" should be "execute '/bin/true'"
    And current resource "error_output" should be "Resource error"

  Scenario: resource with :before notification processing
    Given chef resource is a "before" notification
    When I call "resource_action_start"
    And I call "resource_completed"
    Then "resource_collection_cursor" should be "0"
    And there is "1" resources processed in total
    And current resource "before_notifications" should be "1"
    And current resource "notifying_resource" should be "cucumber[resource]"
    And current resource "notification_type" should be "before"

  Scenario: resource with :immediate notification processing
    Given chef resource is a "immediate" notification
    When I call "resource_action_start"
    And I call "resource_completed"
    Then "resource_collection_cursor" should be "0"
    And there is "1" resources processed in total
    And current resource "immediate_notifications" should be "1"
    And current resource "notifying_resource" should be "cucumber[resource]"
    And current resource "notification_type" should be "immediate"

  Scenario: resource with :delayed notification processing
    Given chef resource is a "delayed" notification
    When I call "resource_action_start"
    And I call "resource_completed"
    Then "resource_collection_cursor" should be "0"
    And there is "1" resources processed in total
    And current resource "delayed_notifications" should be "1"
    And current resource "notifying_resource" should be ""
    And current resource "execution_phase" should be "delayed"
    And current resource "notification_type" should be "delayed"

  Scenario: compile-time resource processing
    Given the "run_phase" is "compile"
    When I call "resource_action_start"
    And I call "resource_completed"
    Then "resource_collection_cursor" should be "0"
    And  current resource "execution_phase" should be "compile"

  Scenario: resource processing - unprocessed
    When I call "resource_action_start"
    And I call "resource_failed"
    And I call "resource_completed"
    And I have a chef resource "execute[/bin/true]" with action "run"
    And I call "converge_failed"
    Then "resource_collection_cursor" should be "1"
    And there is "2" resources processed in total
    And current resource "status" should be "unprocessed"

  Scenario: nested resources processing
    When I have a chef resource "execute[/bin/true]" with action "run"
    And I call "resource_action_start"
    # on execute[/bin/true]
    And I have a chef resource "execute[/bin/false]" with action "run"
    And I call "resource_action_start"
    # on execute[/bin/false]
    And I call "resource_completed"
    # on execute[/bin/false]
    And I have a chef resource "execute[/bin/true]" with action "run"
    And I call "resource_completed"
    # on execute[/bin/true]
    And there is "1" resources processed in total

  Scenario: out-of-bound events processing
    When I have a chef resource "execute[/bin/true]" with action "run"
    And I call "resource_up_to_date"
    And I call "resource_completed"
    Then there is "0" resources processed in total
    And "resource_collection_cursor" should be "0"
