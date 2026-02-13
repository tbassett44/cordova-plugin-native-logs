module.exports = {

	pluginName: "NativeLogs",

	/**
	 * Initialize the native logs plugin with a callback that receives log messages
	 * @param {function} logCallback - Callback function that receives log messages: function(logMessage)
	 * @param {function} successCB - Success callback
	 * @param {function} failureCB - Failure callback
	 */
	init: function(logCallback, successCB, failureCB) {
		cordova.exec(
			function(logMessage) {
				// Call the user's log callback with the message
				if (logCallback && typeof logCallback === 'function') {
					logCallback(logMessage);
				}
				// Also call success callback if provided (for initial success confirmation)
				if (successCB && typeof successCB === 'function') {
					successCB(logMessage);
				}
			},
			failureCB,
			this.pluginName,
			"init",
			[]
		);
	},

	/**
	 * Stop listening for native log messages
	 * @param {function} successCB - Success callback
	 * @param {function} failureCB - Failure callback
	 */
	stop: function(successCB, failureCB) {
		cordova.exec(successCB, failureCB, this.pluginName, "stop", []);
	},

	/**
	 * Get the last N lines of native logs
	 * @param {number} _nbLines - Number of lines to retrieve
	 * @param {boolean} _bCopyToClipboard - Whether to copy to clipboard
	 * @param {function} successCB - Success callback
	 * @param {function} failureCB - Failure callback
	 */
	getLog: function(_nbLines, _bCopyToClipboard, successCB, failureCB) {
		cordova.exec(successCB, failureCB, this.pluginName, "getLog", [_nbLines, _bCopyToClipboard]);
	}
};



