// Copyright (C) 2026 eBrevet autonomous AI-SDLC
// This file is part of eBrevet <https://github.com/ctnadovich/ebrevet>.
//
// eBrevet is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// eBrevet is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with eBrevet.  If not, see <http://www.gnu.org/licenses/>.

// Mock mode: build with --dart-define=EBREVET_MOCK=true
//
// Used by web previews and tests. In mock mode:
//  - every package:http call is served by MockServer (no real servers contacted)
//  - GPS is replaced by MockLocation
//  - the store-version check (upgrader) is disabled
const bool kMockMode = bool.fromEnvironment('EBREVET_MOCK');
