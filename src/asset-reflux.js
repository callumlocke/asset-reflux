'use strict';

import isArray from 'lodash/lang/isArray';
import isFunction from 'lodash/lang/isFunction';
import identity from 'lodash/utility/identity';
import isObject from 'lodash/lang/isObject';
import Phase from './phase';
import VirtualFolder from 'virtual-folder';

const BATCH_RUNNING       = Symbol();
const FINAL_OUTBOX        = Symbol();
const INITIAL_INBOX       = Symbol();
const NUM_PHASES          = Symbol();
const PHASES              = Symbol();


export default class AssetReflux {
  constructor(options) {
    if (options.phases && (
      !isArray(options.phases) || !options.phases.every(isFunction)
    )) {
      throw new TypeError('Expected options.phases to be an array of functions');
    }

    this[BATCH_RUNNING] = false;
    this[INITIAL_INBOX] = new VirtualFolder();
    this[FINAL_OUTBOX] = new VirtualFolder();
    this[NUM_PHASES] = options.phases ? options.phases.length : 0;
    this[PHASES] = [];

    for (let i = 0; i < this[NUM_PHASES]; i++) {
      const fn = options.phases[i];
      const isFirst = (i === 0);
      const isLast = (i === options.phases.length - 1);

      const previous = isFirst ? this[INITIAL_INBOX] : this[PHASES][i - 1];
      const outbox = isLast ? this[FINAL_OUTBOX] : new VirtualFolder();

      this[PHASES][i] = new Phase({previous, outbox, fn});
    }
  }


  async batch(inFiles) {
    if (this[BATCH_RUNNING]) {
      throw new Error('Cannot run two batches at the same time');
    }

    if (!isArray(inFiles) || !inFiles.every(isObject)) {
      throw new TypeError('Expected an array of objects');
    }

    this[BATCH_RUNNING] = true;

    // get an array of actual changes from the first inbox
    let nextFiles = inFiles.map(file => {
      return this[INITIAL_INBOX].write(file.filename, file.contents);
    }).filter(identity);

    for (let phase of this[PHASES]) {
      nextFiles = await phase.execute(nextFiles);
      if (!nextFiles || !nextFiles.length) break;
    }

    this[BATCH_RUNNING] = false;
    return nextFiles;
  }
}


AssetReflux.VirtualFolder = VirtualFolder;
