# Teeworlds External Console

[![NPM version][npm-image]][npm-url] [![Dependency Status][daviddm-image]][daviddm-url]

Teeworlds external console client.

## Installation

Install via npm:

```sh
npm install --save teeworlds-econ
```

Configure Teeworlds external console:

```
ec_port         8303
ec_password     secret
ec_output_level 2
```

## Usage

### Initialize and connect

```js
import TeeworldsEcon from 'teeworlds-econ'

const host = 'localhost'
const port = '8303'
const password = 'secret'

const econ = new TeeworldsEcon(host, port, password);
econ.connect();
```

## Handling game events

```js
econ.on('enter', (player) => {
  console.log('%s has entered the game', player);
});

econ.on('leave', (player) => {
  console.log('%s has left the game', player);
});

econ.on('chat', (player, message) => {
  console.log('%s: "%s"', player, message);
});

econ.on('pickup', (player, weapon) => {
  console.log('%s picked up %s', player, weapon);
});

econ.on('kill', (killer, victim, weapon) => {
  console.log('%s killed %s with %s', killer, victim, weapon);
});
```

## Other
```js
econ.say('gg'); // Send message to chat
econ.motd('Welcome!'); // Set message of the day
econ.exec('sv_map dm2'); // Change current map to dm2
```

## License

LGPL-3.0

[npm-image]: https://badge.fury.io/js/teeworlds-econ.svg
[npm-url]: https://www.npmjs.com/package/teeworlds-econ
[daviddm-image]: https://david-dm.org/black-roland/teeworlds-econ.svg?theme=shields.io
[daviddm-url]: https://david-dm.org/black-roland/teeworlds-econ
