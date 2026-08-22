# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The ISHS Cloud Computing Authors

# GuardDuty Detector (과제지가 요구할 때만: addon_evb_guardduty_enabled = true)
# 리전당 1개만 존재 가능 — 이미 켜져 있으면 apply 가 BadRequest. README 함정 참고.
resource "aws_guardduty_detector" "addon_evb" {
  count = var.addon_evb_guardduty_enabled ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = { Name = "${var.addon_evb_sns_topic_name}-guardduty" }
}
