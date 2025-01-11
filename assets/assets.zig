pub const palettes = @embedFile("palette.dat"); // palettes for tyrian.pic
pub const game_screen = @embedFile("tyrian.pic"); // game interface backgrounds
pub const game_sprites = @embedFile("newsh~.shp");

pub const fonts = @embedFile("tyrian.shp");
pub const texts = @embedFile("tyrian.hdt");

pub const music = @embedFile("music.mus");
pub const sounds = @embedFile("tyrian.snd"); // sound effects, excludes voice samples
pub const voice_samples = @embedFile("voices.snd");
pub const christmas_voice_samples = @embedFile("voicesc.snd");
