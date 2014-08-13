/**
  helper functions
  needs a cleanup
*/

var path = require('path'); // THIS NEEDS TO CHANGE


var isLocalURL = function (url) {
  return url && url.indexOf('//') === -1 && url.indexOf(':') === -1;
};


var isLocalScript = function (attrs) {
  // console.log('isLocalScript', attrs, ((attrs.type == null) || attrs.type === 'application/javascript') && isLocalURL(attrs.src));
  return ((attrs.type == null) || attrs.type === 'application/javascript') && isLocalURL(attrs.src);
};


var isLocalStylesheet = function (attrs) {
  return attrs.rel === 'stylesheet' && isLocalURL(attrs.href);
};

//
// var isBlockableTag = function (tagName, attrs) {
//   return (
//     (tagName === 'script' && isLocalScript(attrs)) ||
//     (tagName === 'link' && isLocalStylesheet(attrs))
//   );
// };


var getBaseRelativeURL = function (refererRelativeURL, referer) {
  if (refererRelativeURL.charAt(0) === '/') {
    return refererRelativeURL.substring(1);
  } else {
    return path.resolve("/" + (path.dirname(referer)), refererRelativeURL).substring(1); // TODO: not using path module!
  }
};


// returns a two-part array: part 0 is the main part of the URL, and part 1 is any query string and/or hash (including the ? or #) or null.
var splitURL = function (url) {

  var queryIndex = url.indexOf('?');
  var hashIndex = url.indexOf('#');
  var appendage = null, appendageStart;

  if (queryIndex !== -1)
    appendageStart = queryIndex;
  if (hashIndex !== -1 && (!appendageStart || hashIndex < queryIndex))
    appendageStart = hashIndex;

  if (appendageStart) {
    appendage = url.substring(appendageStart);
    url = url.substring(0, appendageStart);
  }

  return [url, appendage];
};


var isConditionalComment = function (text) {
  return ((/\[if[^\]]+\]/).test(text) || (/\s*(<!\[endif\])$/).test(text));
};


module.exports = {
  isLocalURL: isLocalURL,
  // isBlockableTag: isBlockableTag,
  getBaseRelativeURL: getBaseRelativeURL,
  splitURL: splitURL,
  isConditionalComment: isConditionalComment
};
