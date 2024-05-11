# planet_test

A simple planet shader based on Sebastian Lague's [Coding Adventure: Procedural Moons and Planets](https://www.youtube.com/watch?v=lctXaT9pxA0) videos. [Github link](https://github.com/SebLague/Solar-System/tree/Episode_02)

![Screenshot from 2024-05-11 14-37-33](https://github.com/masonblier/planet_test/assets/677787/106efdba-1e31-4b1d-8110-08e5eca58c71)

There is currently a bug with how the depth or ray cast is implemented, causing the water to move as you approach.

Uses the [Bevy engine](https://bevyengine.org/) and [Rapier physics engine](https://rapier.rs). Based on the [Bevy Game Template](https://github.com/NiklasEi/bevy_game_template).

# Running from source

* Start the native app: `cargo run`
* Start the web build: `trunk serve`
    * requires [trunk]: `cargo install --locked trunk`
    * requires `wasm32-unknown-unknown` target: `rustup target add wasm32-unknown-unknown`
    * this will serve your app on `8080` and automatically rebuild + reload it after code changes

# License

This project is licensed under [CC0 1.0 Universal](LICENSE)
