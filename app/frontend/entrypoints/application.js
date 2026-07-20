import "bootstrap/dist/css/bootstrap.min.css";
import "bootstrap";

import * as Turbo from '@hotwired/turbo'
Turbo.start()

import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

console.log('Visit the guide for more information: ', 'https://vite-ruby.netlify.app/guide/rails')


