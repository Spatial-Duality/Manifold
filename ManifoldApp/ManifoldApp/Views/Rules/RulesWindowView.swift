// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// This file previously hosted the preview-only Rules surface
// (struct RulesView + RuleCard + legacy helpers). It has been superseded
// by the unified, runtime-backed Rules surface in RulesView.swift.
//
// Left behind intentionally as an empty shim so the Xcode project's
// existing PBXFileReference keeps compiling during the transition. Do
// not add new types here — use RulesView.swift / RuleInspector.swift /
// RuleListTable.swift / RuleBuilder.swift / MatchPreview.swift.

import Foundation
