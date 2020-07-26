window.onload = function() {
    // set the onclick event for every deleteLink
    document.getElementsByClassName("deleteLink").forEach(deleteLink => {
        deleteLink.onclick = function() {
            // delete the order
            fetch(`/${deleteLink.GetAttribute("guid")}`,
                {method: 'DELETE',
                body: `adminGuid=${adminGuid}`});
            // refresh the page
            window.location.reload();
            return false;
        }
    });
}

function reloadOrders() {
    // reload the orders from the XML file
    fetch(`/${adminGuid}/reloadOrders`);
    // refresh the page
    window.location.reload();
}