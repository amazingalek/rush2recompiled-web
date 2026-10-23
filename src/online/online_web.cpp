// Online play on a page (the web build, CMakeLists.txt): there is none. A browser gives a page no UDP sockets for ENet
// and no router to open a port on with UPnP, so in place of online_net.cpp, online_discovery.cpp and online_upnp.cpp
// the web build has these: online isn't available, nothing hosts or joins, and the rest of the game (online_game.cpp,
// online_lobby.cpp, the Online tab) sees an offline machine, as it does on a desktop whose ENet didn't start.

#include <array>
#include <cstdarg>
#include <cstdio>
#include <mutex>
#include <string>
#include <vector>

#include "online.h"

namespace rush2::online {

namespace {
    std::mutex name_mutex;
    std::string my_name;
}

// No session to log to a file: the console only.
void session_log(const char* format, ...) {
    va_list args;
    va_start(args, format);
    std::vfprintf(stderr, format, args);
    va_end(args);
}

bool available() { return false; }

std::string compatibility_key() { return std::string(RUSH2_VERSION) + "-" + RUSH2_BUILD_ID + "-web"; }

bool host(const HostOptions&) { return false; }
bool join(const std::string&) { return false; }
void leave() {}
State state() { return State::Offline; }
bool is_host() { return false; }
int local_slot() { return 0; }
std::vector<RosterEntry> roster() { return {}; }
int max_players_setting() { return 0; }
std::string lobby_name() { return {}; }
uint16_t lobby_port() { return 0; }
std::string last_error() { return "Online play needs the desktop game: a browser can't open its connections."; }
std::string router_status() { return {}; }
RouterPort router_port() { return RouterPort::None; }
std::vector<std::string> local_addresses() { return {}; }
std::string public_address() { return {}; }

void set_local_games(uint8_t) {}
void set_local_mod_cars(const std::array<uint32_t, max_mod_cars>&) {}
void set_local_gameplay(const std::string&) {}

// The name is kept, as the desktop keeps it offline: the Controls tab shows and edits it.
void set_display_name(const std::string& name) {
    std::string out;
    for (char c : name) {
        if (out.size() >= size_t(max_name_length)) {
            break;
        }
        out += (c >= 0x20 && c < 0x7F) ? c : ' ';
    }
    size_t start = out.find_first_not_of(' ');
    size_t end = out.find_last_not_of(' ');
    out = start == std::string::npos ? std::string() : out.substr(start, end - start + 1);
    std::lock_guard lock{ name_mutex };
    my_name = out.empty() ? std::string("Player") : out;
}

std::string display_name() {
    std::lock_guard lock{ name_mutex };
    return my_name;
}

void set_profile_name(const std::string&) {}
void set_cars(const std::vector<LocalPlayer>&) {}
void set_progress(Progress) {}
void set_track_check(uint32_t, bool) {}
uint32_t track_check(const std::string&) { return 0; }
bool start_race(const RaceSettings&) { return false; }
void publish_menu(const MenuState&) {}
bool host_menu(MenuState*) { return false; }
std::vector<LanLobby> lan_lobbies() { return {}; }
bool racing() { return false; }
void submit_local_input(uint32_t, const std::vector<PlayerInput>&) {}
Wait wait_frame_inputs(uint32_t, PlayerInput*, int, bool*) { return Wait::Ended; }
void send_snapshot(uint32_t, const std::vector<uint8_t>&) {}
Wait wait_snapshot(uint32_t, std::vector<uint8_t>*, int) { return Wait::Ended; }
uint32_t input_delay() { return 0; }
uint32_t race_seed() { return 0; }
RaceSettings race_settings() { return {}; }
std::vector<RosterEntry> race_roster() { return {}; }
void report_state_hash(uint32_t, uint32_t) {}
void report_loaded(uint32_t, uint32_t, uint32_t) {}
void race_finished() {}
std::string race_status() { return {}; }
void update() {}

}
