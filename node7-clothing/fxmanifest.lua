fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

author 'NODE7 Development Studios'
name 'node7-clothing'
description 'Server-authoritative NODE7 clothing shops, wearable commands, cash and bank checkout.'
version '2.4.1'

ui_page 'html/dist/index.html'

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'html/dist/index.html',
    'html/dist/app.js',
    'html/dist/app.js.LICENSE.txt',
    'html/dist/checkout-v2.js',
    'html/dist/*.png',
    'html/dist/*.eot',
    'html/dist/*.woff2',
    'html/dist/*.woff',
    'html/dist/*.ttf'
}

dependencies {
    'node7-core',
    'node7-appearance',
    'oxmysql'
}
