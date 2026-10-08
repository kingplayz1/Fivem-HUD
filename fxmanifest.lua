
fx_version 'cerulean'
game 'gta5'

auther 'Bablo Resources Windows 11'

version '2.0.1'

ui_page 'web/dist/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'src/resource/shared/functions.lua',
    'src/resource/shared/debug.lua',
    'src/resource/shared/locale.lua',
    'src/resource/client/constants.lua',
    'src/frameworks/qb/client.lua',
    'src/frameworks/esx/client.lua',
    'src/frameworks/qbox/client.lua',
    'src/frameworks/nd/client.lua',
    'src/frameworks/vrp/client.lua',
    'src/resource/client/minimap.lua',
    'src/resource/client/utils.lua',
    'src/resource/client/main.lua',
    'src/resource/client/nui.lua',
    'src/resource/client/voice.lua',
    'src/resource/client/modules/*.lua'
}

server_scripts {
    'src/resource/shared/functions.lua',
    'src/resource/shared/debug.lua',
    'src/resource/shared/locale.lua',
    'src/frameworks/qb/server.lua',
    'src/frameworks/esx/server.lua',
    'src/frameworks/qbox/server.lua',
    'src/frameworks/nd/server.lua',
    'src/frameworks/vrp/server.lua',
    'src/resource/server/main.lua',
    'src/resource/server/version.lua',
    'src/resource/server/global-config.lua',
    'src/resource/server/mileage.lua',
}

files {
    'web/dist/**/*',
    'assets/*',
    'assets/**/*',
    'stream/*.ytd',
    'stream/*.ydd',
    'stream/*.gfx',
    'locales/*.json',
    'weapons/*.png',
    'weapons/*.webp',
    'audiodirectory/bablo_custom_sounds.awc',
    'audiodirectory/awc.nametable',
    'data/bablo_audioexample_sounds.dat54.rel'
}

data_file 'AUDIO_WAVEPACK' 'audiodirectory'
data_file 'AUDIO_SOUNDDATA' 'data/bablo_audioexample_sounds.dat'

escrow_ignore {
    'config.lua',
    'src/resource/client/voice.lua',
    'src/frameworks/qb/client.lua',
    'src/frameworks/esx/client.lua',
    'src/frameworks/qbox/client.lua',
}

dependency '/assetpacks'
