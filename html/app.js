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
