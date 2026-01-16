// Application JavaScript

console.log('Wry Zig Wrapper App Started');

// Test button functionality
function testMessage() {
    console.log('Test button clicked!');

    const statusText = document.getElementById('status-text');
    const originalText = statusText.textContent;

    // Update status
    statusText.textContent = '✓ Communication test successful!';

    // Change color temporarily
    statusText.parentElement.style.background = '#fff3cd';
    statusText.parentElement.style.color = '#856404';

    // Reset after 2 seconds
    setTimeout(() => {
        statusText.textContent = originalText;
        statusText.parentElement.style.background = '#d4edda';
        statusText.parentElement.style.color = '#155724';
    }, 2000);
}

// Communication with backend
// We'll use window.location to trigger backend actions via custom URL scheme
// The backend intercepts these URLs and returns JSON responses
function showFiles() {
    console.log('Show files button clicked!');

    const fileListDiv = document.getElementById('file-list');
    const fileItems = document.getElementById('file-items');

    // Show loading state
    fileListDiv.style.display = 'block';
    fileItems.innerHTML = '<li style="padding: 10px; color: #6c757d;">Loading files...</li>';

    // Check if we have a custom protocol handler available
    if (window.__wry_backend__) {
        // Use the custom backend API if available
        try {
            const files = window.__wry_backend__.listFiles('.');
            displayFiles(files);
        } catch (error) {
            console.error('Error listing files:', error);
            fileItems.innerHTML = '<li style="padding: 10px; color: #dc3545;">Error: ' + error.message + '</li>';
        }
    } else {
        // Fallback: Use eval to call backend (requires backend to inject JavaScript)
        // This is the mechanism Wry uses for communication
        window.eval(`
            (function() {
                // This will be intercepted by the Rust backend
                window.location.href = 'wry://list-files?path=.';
            })();
        `);
    }
}

// Display files in the UI
function displayFiles(files) {
    const fileItems = document.getElementById('file-items');

    if (!files || files.length === 0) {
        fileItems.innerHTML = '<li style="padding: 10px; color: #6c757d;">No files found or directory is empty.</li>';
        return;
    }

    fileItems.innerHTML = '';

    files.forEach(file => {
        const li = document.createElement('li');
        li.style.cssText = 'padding: 8px 12px; border-bottom: 1px solid #dee2e6; display: flex; align-items: center;';

        const icon = file.is_dir ? '📁' : '📄';
        li.innerHTML = `<span style="margin-right: 8px;">${icon}</span><span style="flex: 1;">${file.name}</span>`;

        if (file.size !== undefined) {
            const size = formatFileSize(file.size);
            li.innerHTML += `<span style="color: #6c757d; font-size: 12px;">${size}</span>`;
        }

        fileItems.appendChild(li);
    });
}

// Format file size for display
function formatFileSize(bytes) {
    if (bytes === undefined) return '';

    const units = ['B', 'KB', 'MB', 'GB'];
    let size = bytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
        size /= 1024;
        unitIndex++;
    }

    return size.toFixed(1) + ' ' + units[unitIndex];
}

// Handle responses from backend
// The backend should inject JavaScript to call this function with data
window.__handleBackendResponse = function(response) {
    console.log('Received backend response:', response);

    if (response.action === 'list-files') {
        displayFiles(response.files);
    }
};

// Log page load
window.addEventListener('DOMContentLoaded', () => {
    console.log('DOM fully loaded');
    console.log('WebView engine ready');
});

// Log window resize
window.addEventListener('resize', () => {
    console.log('Window resized:', window.innerWidth, 'x', window.innerHeight);
});

// Add startup animation
document.addEventListener('DOMContentLoaded', () => {
    const container = document.querySelector('.container');
    container.style.opacity = '0';
    container.style.transform = 'translateY(20px)';
    container.style.transition = 'all 0.5s ease-out';
    
    setTimeout(() => {
        container.style.opacity = '1';
        container.style.transform = 'translateY(0)';
    }, 100);
});
