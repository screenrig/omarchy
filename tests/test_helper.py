import importlib.machinery
import importlib.util
import json
import os
import re
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("helper", os.path.join(HERE, "..", "bin", "screenrig-omarchy"))
spec = importlib.util.spec_from_loader("helper", loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)

# JavaScript's \s, which includes U+2028 and U+2029.
JS_SPACE = "\t\n\v\f\r    -     　﻿"


def parse_jsonc(text):
    """Read a menu file the way Omarchy does: MenuModel.js stripJsonc, then JSON.parse.

    A JavaScript multiline ^ also matches after U+2028 and U+2029, so a line
    separator inside a label followed by // deletes the rest of that row.
    """
    text = re.sub(r"(?:(?<=[\n\r  ])|\A)[%s]*//[^\n]*(?:\n|\Z)" % JS_SPACE, "", text)
    text = re.sub(r",([%s]*[}\]])" % JS_SPACE, r"\1", text)
    return json.loads(text)


SNAP = {
    "screens": [{"id": "scr_A", "label": "Lobby TV", "online": True, "playing_name": "Welcome"},
                {"id": "scr_B", "label": "Kitchen", "online": False, "playing_name": ""}],
    "playlists": [{"id": "pl_1", "name": "Welcome", "approved": True}],
}

USER_MENU = """{
  // Extend the Quickshell Omarchy menu with JSONC.
  "style.lockscreen": {"icon":"x","label":"Lock Screen","action":"omarchy-shell lock explore"}
}
"""


class MenuMerge(unittest.TestCase):
    def test_block_keeps_user_rows_and_parses(self):
        merged = helper.merge_menu(USER_MENU, helper.menu_rows(SNAP))
        menu = parse_jsonc(merged)
        self.assertIn("style.lockscreen", menu)
        self.assertEqual(menu["screenrig.screens.scr_A"]["label"], "Lobby TV")
        self.assertIn("offline", menu["screenrig.screens.scr_B"]["description"])
        self.assertEqual(menu["screenrig.playlists.pl_1"]["action"],
                         "xdg-open https://screenrig.ai/dashboard/playlists/pl_1")

    def test_comment_only_file_keeps_its_comments(self):
        merged = helper.merge_menu("// my notes\n", helper.menu_rows(SNAP))
        self.assertTrue(merged.startswith("// my notes\n{"))
        self.assertEqual(parse_jsonc(merged)["screenrig.screens.scr_A"]["label"], "Lobby TV")

    def test_merge_is_idempotent_and_replaces_block(self):
        once = helper.merge_menu(USER_MENU, helper.menu_rows(SNAP))
        self.assertEqual(helper.merge_menu(once, helper.menu_rows(SNAP)), once)
        fewer = dict(SNAP, screens=SNAP["screens"][:1])
        menu = parse_jsonc(helper.merge_menu(once, helper.menu_rows(fewer)))
        self.assertNotIn("screenrig.screens.scr_B", menu)
        self.assertEqual(once.count("screenrig-omarchy:begin"), 1)

    def test_line_separators_in_names_survive_the_omarchy_reader(self):
        snap = {"screens": [{"id": "scr_A", "label": "Lobby // TV", "online": True, "playing_name": "Loop //x"}],
                "playlists": [{"id": "pl_1", "name": "Menu //board", "approved": True}]}
        merged = helper.merge_menu(USER_MENU, helper.menu_rows(snap))
        menu = parse_jsonc(merged)
        self.assertIn("style.lockscreen", menu)
        self.assertEqual(menu["screenrig.screens.scr_A"]["label"], "Lobby // TV")
        self.assertEqual(menu["screenrig.screens.scr_A.open"]["label"], "Open Lobby // TV")
        self.assertEqual(menu["screenrig.screens.scr_A"]["description"], "screen online Loop //x")
        self.assertEqual(menu["screenrig.playlists.pl_1"]["label"], "Menu //board")
        self.assertEqual(helper.merge_menu(merged, helper.menu_rows(snap)), merged)

    def test_block_written_with_a_raw_line_separator_is_replaced(self):
        bad = helper.merge_menu(USER_MENU, helper.menu_rows(SNAP)).replace("Lobby TV", "Lobby // TV")
        with self.assertRaises(ValueError):
            parse_jsonc(bad)
        fixed = helper.merge_menu(bad, helper.menu_rows(SNAP))
        self.assertEqual(parse_jsonc(fixed)["screenrig.screens.scr_A"]["label"], "Lobby TV")

    def test_empty_object_has_no_trailing_comma(self):
        menu = parse_jsonc(helper.merge_menu("{\n}\n", helper.menu_rows(SNAP)))
        self.assertIn("screenrig", menu)

    def test_remove_restores_user_file(self):
        with tempfile.TemporaryDirectory() as d:
            helper.MENU_FILE = os.path.join(d, "omarchy-menu.jsonc")
            with open(helper.MENU_FILE, "w") as f:
                f.write(USER_MENU)
            self.assertTrue(helper.menu_sync(SNAP))
            self.assertFalse(helper.menu_sync(SNAP))
            self.assertTrue(helper.menu_remove())
            with open(helper.MENU_FILE) as f:
                self.assertEqual(parse_jsonc(f.read()), parse_jsonc(USER_MENU))


class Theme(unittest.TestCase):
    def test_params_from_colors_toml(self):
        with tempfile.NamedTemporaryFile("w", suffix=".toml", delete=False) as f:
            f.write('accent = "#7AA2F7"\nbackground = "#1a1b26ff"\nforeground = "#c0caf5"\nmode = "dark"\n')
        try:
            params = helper.theme_params(helper.read_theme_colors(f.name))
        finally:
            os.unlink(f.name)
        self.assertEqual(params, {"accent": "#7aa2f7", "backgroundColor": "#1a1b26", "textColor": "#c0caf5"})

    def test_legacy_color_slots(self):
        params = helper.theme_params({"color0": "#000000", "color4": "#0000ff", "color7": "#ffffff"})
        self.assertEqual(params["accent"], "#0000ff")

    def test_missing_colors_is_a_problem(self):
        with self.assertRaises(helper.Problem):
            helper.theme_params({"accent": "blue"})


class Screens(unittest.TestCase):
    def test_summary_fields(self):
        raw = {"id": "scr_X", "label": "Foyer", "online": False, "state": "active", "playlist_id": "pl_1",
               "effective_playlist": {"id": "pl_2", "source": "takeover", "until": "2026-11-08T18:00:00Z"},
               "takeover": {"playlist_id": "pl_2", "until": "2026-11-08T18:00:00Z"},
               "display": {"requested": "off"}, "host": {"platform": "android", "capabilities": ["reboot"]},
               "manifest_upgrade": {"state": "current"}}
        s = helper.summarize_screen(raw, {"pl_1": "Default", "pl_2": "Sent"})
        self.assertEqual((s["playlist_name"], s["playing_name"], s["playing_source"]), ("Default", "Sent", "takeover"))
        self.assertTrue(s["has_takeover"] and s["display_off"])
        self.assertEqual(s["capabilities"], ["reboot"])

    def test_media_page_video_advances_on_end(self):
        page = helper.media_page("med_1", "video/mp4")
        self.assertEqual(page["advance"], {"mode": "media_end"})
        self.assertEqual(page["primitives"][0]["primitive"], "video")

    def test_iso_in_is_utc_z(self):
        self.assertTrue(re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", helper.iso_in(10)))


class Token(unittest.TestCase):
    def test_exp_from_jwt(self):
        import base64
        body = base64.urlsafe_b64encode(json.dumps({"exp": 1234}).encode()).decode().rstrip("=")
        self.assertEqual(helper.token_exp("h." + body + ".s"), 1234)
        self.assertEqual(helper.token_exp("garbage"), 0)


class AgentEvents(unittest.TestCase):
    def test_codex_turn(self):
        turn = {}
        events = [
            {"type": "thread.started", "thread_id": "t1"},
            {"type": "item.completed", "item": {"id": "e0", "type": "error", "message": "hook warning"}},
            {"type": "turn.started"},
            {"type": "item.started", "item": {"id": "i2", "type": "command_execution", "command": "/usr/bin/bash -lc 'screenrig screen list'", "exit_code": None}},
            {"type": "item.completed", "item": {"id": "i2", "type": "command_execution", "command": "/usr/bin/bash -lc 'screenrig screen list'", "aggregated_output": "a\nb\n", "exit_code": 0}},
            {"type": "item.completed", "item": {"id": "i3", "type": "agent_message", "text": "Done.\n"}},
        ]
        out = [e for ev in events for e in helper.normalize("codex", ev, turn)]
        self.assertEqual(out[0], {"kind": "session", "session": "t1"})
        self.assertNotIn("error", [e["kind"] for e in out])
        self.assertEqual(out[1]["title"], "screenrig screen list")
        self.assertEqual((out[2]["status"], out[2]["output"]), ("done", "b"))
        self.assertEqual(out[3], {"kind": "text", "text": "Done."})

    def test_claude_turn(self):
        turn = {}
        events = [
            {"type": "system", "subtype": "init", "session_id": "s1"},
            {"type": "assistant", "message": {"content": [{"type": "text", "text": "Checking"},
                                                          {"type": "tool_use", "id": "u1", "name": "Bash", "input": {"command": "screenrig screen list"}}]}},
            {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "u1", "is_error": True, "content": "boom"}]}},
            {"type": "result", "session_id": "s1", "is_error": False, "result": "ok"},
        ]
        out = [e for ev in events for e in helper.normalize("claude", ev, turn)]
        kinds = [e["kind"] for e in out]
        self.assertEqual(kinds, ["session", "text", "tool", "tool", "session"])
        self.assertEqual(out[2]["title"], "Bash  screenrig screen list")
        self.assertEqual((out[3]["status"], out[3]["output"]), ("failed", "boom"))

    def test_tidy_tool_titles(self):
        self.assertEqual(helper.tidy("node /x/y/26.11.237/skills/screenrig/scripts/screenrig-plugin-freshness --host codex --run screen list"),
                         "screenrig screen list")
        self.assertEqual(helper.tidy("cat /home/u/.codex/skills/screenrig/SKILL.md"), "cat SKILL.md")

    def test_resume_commands(self):
        self.assertEqual(helper.agent_command("codex", "t1", "hi")[-3:], ["resume", "t1", "hi"])
        self.assertEqual(helper.agent_command("claude", "s1", "hi")[-2:], ["--resume", "s1"])
        grok = helper.agent_command("grok", "g1", "hi")
        self.assertEqual(grok[-2:], ["--resume", "g1"])
        self.assertEqual(grok[grok.index("--output-format") + 1], "streaming-messages-json")
        with self.assertRaises(helper.Problem):
            helper.agent_command("pi", None, "hi")

    def test_grok_messages_stream(self):
        events = [
            {"type": "system", "subtype": "init", "session_id": "g1"},
            {"type": "assistant", "message": {"content": [{"type": "text", "text": "READY"}]}},
            {"type": "result", "session_id": "g1", "is_error": False, "result": "READY"},
        ]
        out = [entry for event in events for entry in helper.normalize("grok", event, {})]
        self.assertEqual(out, [{"kind": "session", "session": "g1"},
                               {"kind": "text", "text": "READY"},
                               {"kind": "session", "session": "g1"}])


picker_loader = importlib.machinery.SourceFileLoader("picker", os.path.join(HERE, "..", "bin", "screenrig-share-picker"))
picker_spec = importlib.util.spec_from_loader("picker", picker_loader)
picker = importlib.util.module_from_spec(picker_spec)
picker_loader.exec_module(picker)


class LiveCast(unittest.TestCase):
    LIST = ("2514190544[HC>]zen-agent[HT>]Zen Browser[HE>]93906347851936[HA>]"
            "2514433552[HC>]com.t3tools.T3Code[HT>]T3 Code (Beta)[HE>]93906343531712[HA>]")

    def test_picker_maps_hyprland_address_to_portal_id(self):
        self.assertEqual(picker.window_id(hex(93906343531712), self.LIST), "2514433552")
        self.assertEqual(picker.window_id(hex(93906347851936)[2:], self.LIST), "2514190544")
        self.assertIsNone(picker.window_id("0xdead", self.LIST))

    def test_fallback_png_is_a_png(self):
        png = helper.solid_png(4, 2)
        self.assertTrue(png.startswith(b"\x89PNG\r\n\x1a\n") and png.endswith(b"IEND\xaeB`\x82"))


class PluginLookup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.caches = {agent: os.path.join(self.tmp.name, agent) for agent in ("claude", "codex", "grok")}
        patch = mock.patch.object(helper, "PLUGIN_CACHES", self.caches)
        patch.start()
        self.addCleanup(patch.stop)

    def install(self, agent, version="26.11.298"):
        root = os.path.join(self.caches[agent], "screenrig-a1b2c3" if agent == "grok" else version)
        for suffix in ("skills/screenrig/SKILL.md", "cli/dist/bin.js"):
            path = os.path.join(root, suffix)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").close()
        os.makedirs(os.path.join(root, ".claude-plugin"))
        with open(os.path.join(root, ".claude-plugin", "plugin.json"), "w") as f:
            json.dump({"name": "screenrig", "version": version}, f)
        return root

    def test_default_grok_is_ready_when_plugin_is_installed(self):
        for agent in self.caches:
            self.install(agent)
        with mock.patch.object(helper, "default_agent", return_value="grok"), \
             mock.patch.object(helper.shutil, "which", side_effect=lambda name: "/bin/" + name), \
             mock.patch.object(helper, "load_config", return_value={"token": "fixture"}):
            status = helper.onboarding()
        self.assertEqual(status["agent"], "grok")
        self.assertTrue(status["plugin"] and status["cli"] and status["signed_in"])

    def test_uses_installed_integration_when_default_has_no_plugin(self):
        self.install("codex")
        for preferred in ("grok", "claude", "other-agent"):
            with self.subTest(preferred=preferred), \
                 mock.patch.object(helper, "default_agent", return_value=preferred), \
                 mock.patch.object(helper.shutil, "which", side_effect=lambda name: "/bin/" + name):
                self.assertEqual(helper.panel_agent(), "codex")

    def test_ignores_plugin_when_its_agent_executable_is_missing(self):
        self.install("grok")
        self.install("codex")
        with mock.patch.object(helper, "default_agent", return_value="grok"), \
             mock.patch.object(helper.shutil, "which", side_effect=lambda name: "/bin/codex" if name == "codex" else None):
            self.assertEqual(helper.panel_agent(), "codex")

    def test_offers_install_for_available_grok_when_no_plugin_is_installed(self):
        with mock.patch.object(helper, "default_agent", return_value="grok"), \
             mock.patch.object(helper.shutil, "which", side_effect=lambda name: "/bin/grok" if name == "grok" else None), \
             mock.patch.object(helper, "load_config", return_value={}):
            status = helper.onboarding()
        self.assertEqual(status["agent_name"], "Grok")
        self.assertTrue(status["installable"])
        self.assertFalse(status["plugin"])

    def test_grok_bundle_uses_manifest_version_for_cli_selection(self):
        self.install("codex", "26.11.275")
        grok = self.install("grok")
        with mock.patch.dict(os.environ, {"SCREENRIG_CLI": ""}), \
             mock.patch.object(helper.shutil, "which", return_value="/usr/bin/node"):
            self.assertEqual(helper.cli_command(), ["/usr/bin/node", os.path.join(grok, "cli", "dist", "bin.js")])

    def test_newest_bundled_cli_across_agents(self):
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            caches = {"claude": os.path.join(tmp, "claude"), "codex": os.path.join(tmp, "codex")}
            for root, version in (("claude", "26.10.1155"), ("codex", "26.11.275"), ("codex", "26.9.2")):
                path = os.path.join(caches[root], version, "cli", "dist")
                os.makedirs(path)
                open(os.path.join(path, "bin.js"), "w").close()
            with mock.patch.object(helper, "PLUGIN_CACHES", caches), \
                 mock.patch.dict(os.environ, {"SCREENRIG_CLI": ""}), \
                 mock.patch.object(helper.shutil, "which", return_value="/usr/bin/node"):
                self.assertEqual(helper.cli_command(),
                                 ["/usr/bin/node", os.path.join(caches["codex"], "26.11.275", "cli", "dist", "bin.js")])


if __name__ == "__main__":
    unittest.main()
