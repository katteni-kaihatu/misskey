/*
 * SPDX-FileCopyrightText: syuilo and misskey-project
 * SPDX-License-Identifier: AGPL-3.0-only
 */

#include <emscripten.h>
#include "doomstat.h"
#include "p_local.h"
#include "doomgeneric.h"

EMSCRIPTEN_KEEPALIVE pixel_t *gridspace_pixels(void)
{
    return DG_ScreenBuffer;
}

/* Read engine state rather than estimating progress from browser time. */
EMSCRIPTEN_KEEPALIVE int gridspace_stat(int field)
{
    player_t *player = &players[consoleplayer];
    switch (field) {
        case 0: return gamestate;
        case 1: return gameepisode;
        case 2: return gamemap;
        case 3: return gameskill + 1;
        case 4: return player->killcount;
        case 5: return totalkills;
        case 6: return player->itemcount;
        case 7: return totalitems;
        case 8: return player->secretcount;
        case 9: return totalsecret;
        case 10: return leveltime;
        case 11: return player->health;
        case 12: return demoplayback;
        default: return 0;
    }
}

EMSCRIPTEN_KEEPALIVE void gridspace_pause(int paused)
{
    if (paused) emscripten_pause_main_loop();
    else emscripten_resume_main_loop();
}
